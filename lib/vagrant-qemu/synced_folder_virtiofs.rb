require "fileutils"
require "json"
require "log4r"
require "open3"
require "shellwords"
require "tmpdir"

module VagrantPlugins
  module QEMU
    class SyncedFolderVirtioFS < Vagrant.plugin("2", :synced_folder)

      # The daemon and QEMU run inside WSL2, so shares do not need Windows
      # DrvFs paths. Vagrant checks this capability during VM validation.
      def self.wsl_allow_non_drvfs?
        true
      end

      def usable?(machine, raise_error = false)
        return false unless machine.provider_name == :qemu

        binary = machine.provider_config.virtiofsd_bin
        executable = binary && (Vagrant::Util::Which.which(binary) || binary)
        unless executable && File.file?(executable) && File.executable?(executable)
          if raise_error
            raise Errors::VirtiofsdNotFound
          end
          return false
        end

        config = machine.provider_config
        command = config.qemu_bin.nil? ? ["qemu-system-#{config.arch}"] : Array(config.qemu_bin)
        output, status = Open3.capture2e(*command, "-device", "help")
        unless status.success? && output.include?('"vhost-user-fs-pci"')
          raise Errors::ConfigError, err: "QEMU must support vhost-user-fs-pci for qemu_virtiofs synced folders." if raise_error
          return false
        end
        true
      rescue Errno::ENOENT, Errno::EACCES
        raise Errors::ConfigError, err: "Cannot execute QEMU to check vhost-user-fs-pci support." if raise_error
        false
      end

      # Both -m and the backend must use the same whole-MiB size. Rational
      # arithmetic avoids floating point rounding at exact MiB boundaries.
      def self.shared_memory_size(value)
        match = /\A(\d+(?:\.\d+)?)([KMGT]?)\z/i.match(value.to_s)
        unless match && Rational(match[1]).positive?
          raise Errors::ConfigError, err: "VirtioFS requires a positive qe.memory (MiB or a K/M/G/T suffix); nil is not supported."
        end
        units = { "" => 1, "K" => Rational(1, 1024), "M" => 1, "G" => 1024, "T" => 1024 * 1024 }
        "#{(Rational(match[1]) * units.fetch(match[2].upcase)).ceil}M"
      end

      def prepare(machine, folders, opts)
        @logger = Log4r::Logger.new("vagrant_qemu::synced_folder_virtiofs")
        machine.provider_config.virtiofs_qemu_args = []
        memory = normalized_memory(machine.provider_config.memory) unless folders.empty?
        cleanup(machine, {})
        return if folders.empty?

        # Use /tmp for socket files — Unix domain sockets have a 104-byte path limit
        # on macOS, and Vagrant data_dir paths are often too long.
        # PID files and logs stay in the data dir for persistence.
        virtiofs_dir = machine.data_dir.join("virtiofs")
        FileUtils.mkdir_p(virtiofs_dir)
        socket_dir = Dir.tmpdir
        virtiofsd = machine.provider_config.virtiofsd_bin
        # QEMU creates and immediately unlinks its backing file when given a
        # directory. No named guest RAM file remains after shutdown.
        mem_path = Dir.tmpdir
        extra_args = %W(
          -object memory-backend-file,id=mem,size=#{memory},mem-path=#{mem_path},share=on
          -numa node,memdev=mem
        )

        mounts = {}
        sorted_folders = folders.sort_by { |_id, opts| opts[:guestpath] }
        sorted_folders.each_with_index do |(_id, folder_opts), i|
          hostpath = File.expand_path(folder_opts[:hostpath])
          tag = "virtiofs#{i}"
          socket_id = "vqemu-#{machine.id}-#{tag}"
          socket_path = File.join(socket_dir, "#{socket_id}.sock")
          pid_file = virtiofs_dir.join("#{tag}.pid").to_s

          # Clean up any stale virtiofsd from a previous run
          cleanup_virtiofsd(pid_file, socket_path, virtiofsd)

          # Start virtiofsd
          log_file = virtiofs_dir.join("#{tag}.log").to_s
          host_uid = Process.uid
          host_gid = Process.gid
          virtiofsd_args = [
            virtiofsd,
            "--socket-path=#{socket_path}",
            "--shared-dir=#{hostpath}",
            "--sandbox=none",
            "--inode-file-handles=never",
          ]

          # Add UID/GID mapping if virtiofsd supports it (v1.13+)
          translate_supported = virtiofsd_help(virtiofsd).include?("--translate-uid")
          if translate_supported
            virtiofsd_args += [
              "--translate-uid", "map:#{machine.provider_config.virtiofs_guest_uid}:#{host_uid}:1",
              "--translate-gid", "map:#{machine.provider_config.virtiofs_guest_gid}:#{host_gid}:1",
            ]
          end
          # Append user-supplied extra virtiofsd args from provider config
          extra_vfs = machine.provider_config.extra_virtiofsd_args
          virtiofsd_args += extra_vfs if extra_vfs.is_a?(Array) && !extra_vfs.empty?
          pid = spawn(*virtiofsd_args, in: File::NULL, [:out, :err] => [log_file, "w"], pgroup: true)
          waiter = Process.detach(pid)
          # Record ownership before waiting so failed startup can be cleaned up.
          File.write(pid_file, pid.to_s)
          File.write(virtiofs_dir.join("#{tag}.sock_path").to_s, socket_path)
          identity = process_identity(pid)
          if identity
            File.write(pid_file.sub(/\.pid$/, ".process.json"), JSON.generate(
              "identity" => identity, "binary" => virtiofsd))
          end

          # The socket path can appear before virtiofsd starts listening.
          30.times do
            break if File.socket?(socket_path)
            sleep 0.1
          end

          # Give the listener time to finish startup before QEMU connects.
          sleep 0.2 if File.socket?(socket_path)

          alive = process_alive?(pid)
          unless File.socket?(socket_path) && alive
            status = waiter.value unless alive
            log = File.read(log_file)
            machine.ui.error("virtiofsd pid #{pid} exited with #{status.inspect}") if status
            machine.ui.error("virtiofsd log (#{log_file}):\n#{log.empty? ? '(empty)' : log}")
            raise Errors::VirtiofsdStartFailed,
              hostpath: hostpath,
              log_file: log_file
          end

          mounts[tag] = folder_opts[:guestpath]
          machine.ui.info("virtiofsd started (pid #{pid}) sharing #{hostpath}")

          extra_args += %W(
            -chardev socket,id=char_#{tag},path=#{socket_path}
            -device vhost-user-fs-pci,chardev=char_#{tag},tag=#{tag}
          )
        end

        # StartInstance combines these with user QEMU args for this start only.
        File.write(virtiofs_dir.join("mounts.json"), JSON.generate(mounts))
        machine.provider_config.virtiofs_qemu_args = extra_args
      rescue StandardError
        cleanup(machine, preserve_logs: true)
        raise
      end

      def enable(machine, folders, opts)
        # Mounting happens in MountVirtioFS action after boot,
        # since the guest isn't available when SyncedFolders runs.
      end

      def disable(machine, folders, opts)
        folders.each do |_id, folder_opts|
          guestpath = folder_opts[:guestpath]
          machine.communicate.sudo("umount #{Shellwords.escape(guestpath)} 2>/dev/null || true")
        end
      end

      def cleanup(machine, opts)
        virtiofs_dir = machine.data_dir.join("virtiofs")
        return unless virtiofs_dir.directory?

        Dir.glob(virtiofs_dir.join("*.pid").to_s).each do |pid_file|
          sock_path_file = pid_file.sub(/\.pid$/, ".sock_path")
          sock_file = File.exist?(sock_path_file) ? File.read(sock_path_file).strip : nil
          cleanup_virtiofsd(pid_file, sock_file, machine.provider_config.virtiofsd_bin)
          File.delete(sock_path_file) if File.exist?(sock_path_file)
        end

        if opts[:preserve_logs]
          FileUtils.rm_f(virtiofs_dir.join("mounts.json"))
        else
          FileUtils.rm_rf(virtiofs_dir)
        end
        machine.ui.info("virtiofsd stopped") if machine.ui
      end

      private

      def normalized_memory(value)
        self.class.shared_memory_size(value)
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      def process_identity(pid)
        return unless process_alive?(pid)
        # lstart distinguishes a reused PID; args verifies our daemon and socket.
        output, status = Open3.capture2e({ "LC_ALL" => "C" }, "ps", "-ww", "-p", pid.to_s, "-o", "lstart=", "-o", "args=")
        output.strip if status.success? && !output.strip.empty?
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end

      def owned_daemon?(pid, socket_path, binary, saved_identity)
        return false unless socket_path && binary
        identity = process_identity(pid)
        return false unless identity && (!saved_identity || identity == saved_identity)
        # ps prints the start time as five words before the command line.
        command = identity.split(/\s+/, 6).last
        binary_name = File.basename(binary)
        command.match?(/(?:\A|\s)(?:\S*\/)?#{Regexp.escape(binary_name)}(?:\s|\z)/) &&
          command.include?("--socket-path=#{socket_path}")
      end

      def cleanup_virtiofsd(pid_file, socket_path, binary)
        process_file = pid_file.sub(/\.pid$/, ".process.json")
        if File.exist?(pid_file)
          contents = File.read(pid_file).strip
          pid = contents.match?(/\A[1-9]\d*\z/) ? contents.to_i : nil
          record = File.file?(process_file) ? JSON.parse(File.read(process_file)) : {}
          binary = record.fetch("binary", binary)
          identity = record["identity"]
          begin
            if pid && owned_daemon?(pid, socket_path, binary, identity)
              Process.kill("TERM", pid)
              5.times do
                break unless owned_daemon?(pid, socket_path, binary, identity)
                sleep 0.5
              end
              Process.kill("KILL", pid) if owned_daemon?(pid, socket_path, binary, identity)
            end
          rescue Errno::ESRCH, Errno::EPERM
            # Dead, reused, or inaccessible PIDs must not block lifecycle actions.
          end
        end
      rescue JSON::ParserError
        # Corrupt ownership records are insufficient authority to signal a PID.
      ensure
        FileUtils.rm_f([pid_file, process_file])
        FileUtils.rm_f(socket_path) if socket_path
      end

      def virtiofsd_help(binary)
        output, _status = Open3.capture2e(binary, "--help")
        output
      rescue Errno::ENOENT, Errno::EACCES
        ""
      end
    end
  end
end
