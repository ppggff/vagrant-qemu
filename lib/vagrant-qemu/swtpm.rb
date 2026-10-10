require "fileutils"
require "fiddle/import"
require "json"
require "pathname"
require "securerandom"
require "vagrant/util/which"

module VagrantPlugins
  module QEMU
    # Only the Provider launches, retains and removes a Machine's TPM backend.
    class Swtpm
      attr_reader :state_dir, :record_path, :control_path

      def self.validate_request(enabled, arch)
        raise Errors::ConfigError, err: "tpm must be true or false" unless [true, false].include?(enabled)
        return unless enabled
        unless !Vagrant::Util::Platform.windows? && RbConfig::CONFIG["host_os"] =~ /linux/ && arch == "x86_64"
          raise Errors::ConfigError, err: "TPM2 emulation requires Linux x86_64; Windows TPM is unsupported"
        end
      end

      def initialize(state_dir, runtime_dir, socket_dir)
        @state_dir = Pathname.new(state_dir)
        @runtime_dir = Pathname.new(runtime_dir)
        @socket_dir = Pathname.new(socket_dir)
        @record_path = @runtime_dir.join("swtpm.json")
        @control_path = @socket_dir.join("tpm-control.sock")
      end

      def start(binary)
        self.class.validate_request(true, "x86_64")
        private_directory(@state_dir, create: true)
        private_directory(@socket_dir)
        raise Errors::ConfigError, err: "TPM option paths cannot contain commas" if [@state_dir, @control_path].any? { |path| path.to_s.include?(",") }
        stop if @record_path.exist?
        executable = Vagrant::Util::Which.which(binary.to_s)
        executable ||= binary.to_s if File.executable?(binary.to_s)
        raise Errors::ConfigError, err: "swtpm executable unavailable: #{binary}" unless executable
        executable = File.realpath(executable)
        # Prove kernel support before launching a process that needs this owner.
        pidfd(Process.pid).close
        # QEMU passes an anonymous Unix data FD over this control socket. A
        # --server listener preoccupies that FD and rejects CMD_SET_DATAFD.
        command = [executable, "socket", "--tpm2", "--tpmstate", "dir=#{@state_dir},mode=0600",
                   "--ctrl", "type=unixio,path=#{@control_path},mode=0600"]
        log_path = @runtime_dir.join("swtpm-stdio.log")
        log = File.open(log_path, File::WRONLY | File::CREAT | File::APPEND, 0600)
        descriptor = nil
        pid = nil
        begin
          pid = Process.spawn(*command, pgroup: true, in: File::NULL, out: log, err: log)
          descriptor = pidfd(pid)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
          until @control_path.socket?
            raise Errors::ConfigError, err: "swtpm exited before creating its local channels" if exited?(descriptor)
            raise Errors::ConfigError, err: "swtpm local channels were not ready within five seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            sleep 0.02
          end
          record = identity(pid).merge("command" => command, "state_dir" => @state_dir.to_s,
                                      "control_path" => @control_path.to_s)
          unless record["executable"] == executable && record["argv"] == command
            raise Errors::ConfigError, err: "Spawned TPM identity does not match the exact executable and Machine state"
          end
          write_record(record)
          record
        rescue Exception
          if descriptor
            terminate(descriptor)
            reap(pid)
            remove_runtime
          elsif pid
            # An unreaped child cannot have its PID reused. Never use this path
            # for a persisted record or a process from a previous CLI.
            begin
              if Process.waitpid(pid, Process::WNOHANG).nil?
                Process.kill("TERM", pid)
                Process.waitpid(pid)
              end
            rescue Errno::ECHILD, Errno::ESRCH
            end
          end
          raise
        ensure
          descriptor.close if descriptor && !descriptor.closed?
          log.close
        end
      end

      def stop
        return unless @record_path.exist? || @record_path.symlink?
        stat = @record_path.lstat
        unless stat.file? && stat.uid == Process.euid && (stat.mode & 0077).zero?
          raise Errors::ConfigError, err: "TPM owner record is not an owned private file"
        end
        record = JSON.parse(@record_path.read)
        unless record["state_dir"] == @state_dir.to_s && record["control_path"] == @control_path.to_s
          raise Errors::ConfigError, err: "TPM owner record does not belong to this Machine"
        end
        descriptor = nil
        begin
          descriptor = pidfd(Integer(record.fetch("pid")))
          unless exited?(descriptor)
            actual = identity(record.fetch("pid"))
            unless %w[pid uid start_ticks executable argv].all? { |key| actual[key] == record[key] }
              raise Errors::ConfigError, err: "TPM PID identity changed; no signal or state removal is authorized"
            end
            terminate(descriptor)
          end
          reap(record.fetch("pid"))
        rescue Errno::ESRCH
          # Original PID no longer exists; no process is signalled.
        ensure
          descriptor.close if descriptor && !descriptor.closed?
        end
        remove_runtime
      end

      private

      def private_directory(path, create: false)
        if create && !path.exist? && !path.symlink?
          Dir.mkdir(path, 0700)
        end
        stat = path.lstat
        unless stat.directory? && !stat.symlink? && stat.uid == Process.euid && (stat.mode & 0077).zero?
          raise Errors::ConfigError, err: "TPM requires an owned private nonsymlink directory: #{path}"
        end
      end

      def api
        @api ||= Module.new do
          extend Fiddle::Importer
          dlload Fiddle.dlopen(nil)
          extern "int pidfd_open(int, unsigned int)"
          extern "int pidfd_send_signal(int, int, void*, unsigned int)"
        end
      rescue Fiddle::DLError
        raise Errors::ConfigError, err: "TPM requires libc pidfd_open and pidfd_send_signal exports; this host is unsupported"
      end

      def pidfd(pid)
        descriptor = api.pidfd_open(pid, 0)
        raise SystemCallError.new("pidfd_open", Fiddle.last_error) if descriptor < 0
        IO.for_fd(descriptor)
      end

      def identity(pid)
        process = Pathname.new("/proc").join(pid.to_s)
        fields = process.join("stat").read.split(") ", 2).last.split
        {"pid" => pid, "uid" => process.stat.uid, "start_ticks" => fields.fetch(19),
         "executable" => process.join("exe").realpath.to_s,
         "argv" => process.join("cmdline").binread.split("\0")}
      end

      def exited?(descriptor)
        !IO.select([descriptor], nil, nil, 0).nil?
      end

      def terminate(descriptor)
        return if exited?(descriptor)
        signal(descriptor, "TERM")
        unless IO.select([descriptor], nil, nil, 5)
          signal(descriptor, "KILL")
          unless IO.select([descriptor], nil, nil, 5)
            raise Errors::ConfigError, err: "Owned TPM process did not terminate; state retained"
          end
        end
      end

      def signal(descriptor, name)
        result = api.pidfd_send_signal(descriptor.fileno, Signal.list.fetch(name), 0, 0)
        raise SystemCallError.new("pidfd_send_signal", Fiddle.last_error) if result < 0
      end

      def reap(pid)
        Process.waitpid(pid, Process::WNOHANG)
      rescue Errno::ECHILD
        # A later Vagrant CLI is not the original process's parent.
      end

      def write_record(record)
        temporary = @runtime_dir.join(".swtpm-#{SecureRandom.hex(6)}.json")
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0600) do |stream|
          stream.write(JSON.generate(record))
          stream.flush
          stream.fsync
        end
        File.rename(temporary, @record_path)
      ensure
        File.unlink(temporary) if temporary && temporary.exist?
      end

      def remove_runtime
        if @socket_dir.exist? || @socket_dir.symlink?
          private_directory(@socket_dir)
          if @control_path.exist? || @control_path.symlink?
            stat = @control_path.lstat
            unless stat.socket? && stat.uid == Process.euid
              raise Errors::ConfigError, err: "TPM cleanup refuses a nonowned socket: #{@control_path}"
            end
            @control_path.unlink
          end
        end
        @record_path.unlink if @record_path.exist?
      end
    end
  end
end
