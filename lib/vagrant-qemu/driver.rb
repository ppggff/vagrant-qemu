require 'log4r'
require 'childprocess'
require 'securerandom'
require 'yaml'
require 'digest'
require 'socket'
require 'fiddle/import'
require 'json'
require 'tmpdir'

require "vagrant/util/busy"
require 'vagrant/util/io'
require "vagrant/util/safe_chdir"
require "vagrant/util/subprocess"
require "vagrant/util/which"

require 'timeout'
require_relative "plugin"
require_relative "network"

module VagrantPlugins
  module QEMU
    class Driver
      # @return [String] VM ID
      attr_reader :vm_id
      attr_reader :data_dir
      attr_reader :tmp_dir
      attr_reader :attached_drives
      # @return [Integer, nil] Runtime SSH port (may differ from config after collision correction)
      attr_reader :ssh_port

      def initialize(id, dir, tmp)
        @vm_id = id
        @data_dir = dir
        @tmp_dir = tmp.join("vagrant-qemu")
        @attached_drives = {disk: [], floppy: [], dvd: []}
        @ssh_port = nil
        @logger = Log4r::Logger.new("vagrant_qemu::driver")
      end

      def get_current_state
        case
        when running?
          :running
        when created?
          :stopped
        else
          :not_created
        end
      end

      def delete
        raise Errors::ConfigError, err: "Cannot delete a running QEMU Machine" if running?
        if created?
          id_dir = @data_dir.join(@vm_id)
          [local_socket('monitor'), local_socket('serial')].each { |path| FileUtils.rm_f(path) } if windows?
          FileUtils.rm_rf(id_dir)
          id_tmp_dir = @tmp_dir.join(@vm_id)
          FileUtils.rm_rf(id_tmp_dir)
        end
      end

      def start(options)
        if !running?
          id_dir = @data_dir.join(@vm_id)

          image_path = Array.new
          image_count = id_dir.glob("linked-box*.img").count
          for i in 0..image_count-1 do
            suffix_index = i > 0 ? "-#{i}" : ''
            image_path.append(id_dir.join("linked-box#{suffix_index}.img").to_s)
          end

          id_tmp_dir = @tmp_dir.join(@vm_id)
          FileUtils.mkdir_p(id_tmp_dir)

          # Persist only the runtime state we need to read back later
          persisted_state = {
            :ssh_port => options[:ssh_port],
            :control_port => options[:control_port],
          }
          options_file = id_tmp_dir.join("options.yml")
          File.write(options_file, persisted_state.to_yaml)

          control_socket = ""
          if !options[:control_port].nil?
            control_socket = "port=#{options[:control_port]},host=localhost,ipv4=on"
          else
            unix_socket_path = id_tmp_dir.join("qemu_socket").to_s
            control_socket = "path=#{unix_socket_path}"
          end

          debug_socket = ""
          if !options[:debug_port].nil?
            debug_socket = "port=#{options[:debug_port]},host=localhost,ipv4=on"
          else
            unix_socket_serial_path = id_tmp_dir.join("qemu_socket_serial").to_s
            debug_socket = "path=#{unix_socket_serial_path}"
          end

          cmd = []
          if options[:qemu_bin].nil?
            cmd += %W(qemu-system-#{options[:arch]})
          else
            if options[:qemu_bin].kind_of?(Array)
              cmd += options[:qemu_bin]
            else
              cmd << options[:qemu_bin]
            end
          end

          # Validate that the QEMU binary exists
          qemu_binary = cmd.first
          if !Vagrant::Util::Which.which(qemu_binary) && !File.executable?(qemu_binary)
            raise Errors::QemuBinaryNotFound, binary: qemu_binary
          end

          # basic
          cmd += %W(-machine #{options[:machine]}) if !options[:machine].nil?
          cmd += %W(-cpu #{options[:cpu]}) if !options[:cpu].nil?
          cmd += %W(-smp #{options[:smp]}) if !options[:smp].nil?
          cmd += %W(-m #{options[:memory]}) if !options[:memory].nil?

          # network
          launch_prefix = []
          if !options[:net_device].nil?
            private_networks = options[:private_networks] || []
            use_advanced = options[:advanced_network] && !private_networks.empty?

            if use_advanced
              # Dual-NIC: NIC 0 = user-mode (SSH + port forwarding), NIC 1 = advanced backend
              pn = private_networks.first
              mac0, mac1 = Network.nic_macs(@vm_id, pn)

              # NIC 0: user-mode
              cmd += %W(-device #{options[:net_device]},netdev=net0,mac=#{mac0})
              hostfwd = "hostfwd=tcp:#{options[:ssh_host] || '127.0.0.1'}:#{options[:ssh_port]}-:22"
              options[:ports].each do |v|
                hostfwd += ",hostfwd=#{v}"
              end
              extra_netdev = ""
              if !options[:extra_netdev_args].nil?
                extra_netdev = ",#{options[:extra_netdev_args]}"
              end
              cmd += %W(-netdev user,id=net0,#{hostfwd}#{extra_netdev})

              # NIC 1: platform-specific backend
              # (the static-IP cloud-init seed is built and attached by the
              # CloudInitNetwork action, not here)
              backend = Network.backend_for(options[:net_mode])
              backend.preflight!(options, qemu_binary)
              cmd += %W(-device #{options[:net_device]},netdev=net1,mac=#{mac1})
              cmd += backend.build_netdev_args("net1", options)
              # launch_prefix is applied under the same gate as build_netdev_args
              # (empty for every backend except socket_vmnet's wrapper route).
              launch_prefix = backend.launch_prefix(options)
            else
              # Single NIC: user-mode only (original behavior, no cloud-init)
              cmd += %W(-device #{options[:net_device]},netdev=net0)

              hostfwd = "hostfwd=tcp:#{options[:ssh_host] || '127.0.0.1'}:#{options[:ssh_port]}-:22"
              options[:ports].each do |v|
                hostfwd += ",hostfwd=#{v}"
              end
              extra_netdev = ""
              if !options[:extra_netdev_args].nil?
                extra_netdev = ",#{options[:extra_netdev_args]}"
              end
              cmd += %W(-netdev user,id=net0,#{hostfwd}#{extra_netdev})
            end
          end

          # drive
          diskid = 0
          extra_drive_args = ""
          if !options[:extra_drive_args].nil?
            extra_drive_args = ",#{options[:extra_drive_args]}"
          end

          if !options[:drive_interface].nil?
            image_path.each do |img|
              cmd += %W(-drive if=#{options[:drive_interface]},id=disk#{diskid},format=qcow2,file=#{img}#{extra_drive_args})
              diskid += 1
            end
          end
          if options[:firmware]
            cmd += ["-drive", "if=pflash,format=raw,unit=0,file=#{id_dir.join('firmware.fd')},readonly=on"]
            cmd += ["-drive", "if=pflash,format=raw,unit=1,file=#{id_dir.join('efi-vars.fd')}"]
          elsif options[:arch] == "aarch64" && !options[:firmware_format].nil?
            fm1_path = id_dir.join("edk2-aarch64-code.fd").to_s
            fm2_path = id_dir.join("edk2-arm-vars.fd").to_s
            cmd += %W(-drive if=pflash,format=#{options[:firmware_format]},file=#{fm1_path},readonly=on)
            cmd += %W(-drive if=pflash,format=#{options[:firmware_format]},file=#{fm2_path})
          end

          dvd_index = 1
          @attached_drives[:dvd].each do |disk|
            cmd += %W(-drive file=#{disk[:Path]},index=#{dvd_index},media=cdrom)
            dvd_index += 1
          end
          if !options[:drive_interface].nil?
            @attached_drives[:disk].each do |disk|
              cmd += %W(-drive if=#{options[:drive_interface]},id=disk#{diskid},format=qcow2,file=#{disk[:Path]}#{extra_drive_args})
              diskid += 1
            end
          end

          # control
          pid_file = id_tmp_dir.join("qemu.pid").to_s
          if windows?
            raise Errors::ConfigError, err: "Windows monitor/serial must use local sockets" if options[:control_port] || options[:debug_port]
            cmd += ["-chardev", "socket,id=mon0,path=#{local_socket('monitor')},server=on,wait=off"]
          else
            cmd += %W(-chardev socket,id=mon0,#{control_socket},server=on,wait=off)
          end
          cmd += ["-mon", "chardev=mon0,mode=#{options[:control_port] ? 'readline' : 'control'}"]
          serial_log = ""
          if options[:serial_log_file]
            FileUtils.mkdir_p(File.dirname(options[:serial_log_file]))
            serial_log = ",logfile=#{options[:serial_log_file]},logappend=on"
          end
          if windows?
            cmd += ["-chardev", "socket,id=ser0,path=#{local_socket('serial')},server=on,wait=off#{serial_log}"]
          else
            cmd += %W(-chardev socket,id=ser0,#{debug_socket},server=on,wait=off#{serial_log})
          end
          cmd += %W(-serial chardev:ser0)
          cmd += %W(-pidfile #{pid_file})
          if !options[:no_daemonize] && !windows?
            cmd += %W(-daemonize)
          end

          # other default
          cmd += options[:other_default]

          # user-defined
          cmd += options[:extra_qemu_args]

          # socket_vmnet wrapper route: launch qemu under socket_vmnet_client
          # (empty prefix otherwise -> zero difference from the current path).
          cmd = launch_prefix + cmd

          opts = {:detach => options[:no_daemonize] || windows?}
          execute(*cmd, **opts)
          if running?
            control = options[:control_port] ? {transport: "tcp", host: "localhost", port: options[:control_port], protocol: "hmp"} : {transport: "unix", path: windows? ? local_socket('monitor') : id_tmp_dir.join("qemu_socket").to_s, protocol: "qmp"}
            serial = options[:debug_port] ? {transport: "tcp", host: "localhost", port: options[:debug_port], slot: 1} : {transport: "unix", path: windows? ? local_socket('serial') : id_tmp_dir.join("qemu_socket_serial").to_s, slot: 1}
            firmware = options[:firmware] ? id_dir.join("firmware.fd").to_s : (options[:arch] == "aarch64" && options[:firmware_format] ? id_dir.join("edk2-aarch64-code.fd").to_s : nil)
            efi_vars = options[:firmware] ? id_dir.join("efi-vars.fd").to_s : (options[:arch] == "aarch64" && options[:firmware_format] ? id_dir.join("edk2-arm-vars.fd").to_s : nil)
            runtime = {schema_version: 1, vm_id: @vm_id, pid: process_id, argv: cmd, control: control, serial: serial, firmware: firmware, efi_vars: efi_vars, serial_log_file: options[:serial_log_file]}
            File.write(id_tmp_dir.join("runtime.json"), JSON.pretty_generate(runtime))
          end
        end
      end

      def stop(options)
        return unless running?

        opts = with_persisted_control_port(options)
        timeout = options[:graceful_timeout] || 60

        # 1. ACPI power button (graceful). Only works if a live guest OS is
        #    there to act on it -- e.g. NOT after `systemctl halt`, which leaves
        #    QEMU running with a halted, unresponsive guest.
        send_monitor(opts, "system_powerdown")
        return unless still_running_after?(timeout)

        # 2. Powerdown didn't take. Ask QEMU itself to quit: it stops the VM,
        #    flushes and closes the qcow2 images, then exits cleanly. Does not
        #    depend on the guest, only on the monitor being reachable.
        @logger.warn("VM did not power down within #{timeout}s; sending 'quit' to QEMU")
        send_monitor(opts, "quit")
        return unless still_running_after?(timeout)

        # 3. Last resort: SIGKILL the QEMU process (no flush/cleanup).
        @logger.warn("VM still running after 'quit'; forcing kill")
        force_kill
        raise Errors::ConfigError, err: "QEMU did not terminate after forced halt" if still_running_after?(5)
      end

      private

      def windows?
        Vagrant::Util::Platform.windows?
      end

      def windows_running?(pid)
        api = windows_process_api
        handle = api.OpenProcess(0x00100000, 0, pid)
        return false if handle.to_i.zero?
        begin
          result = api.WaitForSingleObject(handle, 0)
          raise Errors::ConfigError, err: "Cannot determine QEMU process state" unless [0, 258].include?(result)
          result == 258
        ensure
          api.CloseHandle(handle)
        end
      end

      def windows_process_api
        @windows_process_api ||= Module.new do
          extend Fiddle::Importer
          dlload "kernel32.dll"
          extern "void* OpenProcess(unsigned long, int, unsigned long)"
          extern "unsigned long WaitForSingleObject(void*, unsigned long)"
          extern "int CloseHandle(void*)"
        end
      end

      def local_socket(channel)
        Pathname.new(Dir.tmpdir).join("vq-#{Digest::SHA256.hexdigest(@data_dir.expand_path.to_s + @vm_id)[0, 24]}-#{channel}.sock").to_s
      end

      def process_id
        path = @tmp_dir.join(@vm_id, "qemu.pid")
        return nil unless path.file?
        text = File.read(path).strip
        return nil unless text.match?(/\A[1-9][0-9]*\z/)
        Integer(text)
      end

      # Prefer the control_port the VM was actually started with (persisted
      # in options.yml) so halt still works after a Vagrantfile edit.
      def with_persisted_control_port(options)
        options_file = @tmp_dir.join(@vm_id).join("options.yml")
        return options if !options_file.file?

        persisted = YAML.safe_load(File.read(options_file), permitted_classes: [Symbol]) rescue nil
        return options if persisted.nil? || !persisted.key?(:control_port)

        options.merge(:control_port => persisted[:control_port])
      end

      # Send a single QEMU monitor command over the control channel (TCP
      # control_port if set, else the unix monitor socket). Best-effort: the
      # socket may already be gone (e.g. QEMU exited from a prior command), so
      # connection errors are swallowed.
      def send_monitor(options, command)
        if options[:control_port].nil?
          Timeout.timeout(5) do
            path = windows? ? local_socket('monitor') : @tmp_dir.join(@vm_id, "qemu_socket").to_s
            Socket.unix(path) do |pipe|
              JSON.parse(pipe.gets)
              pipe.puts(JSON.generate(execute: "qmp_capabilities"))
              loop do
                response = JSON.parse(pipe.gets)
                break if response.key?("return") || response.key?("error")
              end
              pipe.puts(JSON.generate(execute: command))
              loop do
                response = JSON.parse(pipe.gets)
                break if response.key?("return") || response.key?("error")
              end
            end
          end
        else
          Socket.tcp("localhost", options[:control_port], connect_timeout: 5) do |sock|
            sock.print "#{command}\n"
            sock.close_write
            sock.read rescue nil
          end
        end
      rescue => e
        @logger.debug("monitor command '#{command}' failed: #{e}") if @logger
      end

      # Poll for up to `timeout` seconds. Return false as soon as the VM has
      # stopped; return true if it is still running when the timeout elapses.
      def still_running_after?(timeout)
        timeout.times do
          return false unless running?
          sleep 1
        end
        running?
      end

      def force_kill
        pid = process_id
        return unless pid
        begin
          Process.kill("KILL", pid)
        rescue Errno::ESRCH
          # Process already gone
        end
      end

      public

      def get_ssh_port(default_port)
        id_tmp_dir = @tmp_dir.join(@vm_id)
        options_file = id_tmp_dir.join("options.yml")

        port = default_port
        if options_file.file?
          # safe_load + File.read (not safe_load_file) so older Psych works too
          options = YAML.safe_load(File.read(options_file), permitted_classes: [Symbol]) rescue nil
          port = options[:ssh_port] if !options.nil? && options.key?(:ssh_port)
        end

        @ssh_port = port
      end

      def import(options)
        new_id = "vq_" + SecureRandom.urlsafe_base64(8)

        # Make dir
        id_dir = @data_dir.join(new_id)
        FileUtils.mkdir_p(id_dir)
        id_tmp_dir = @tmp_dir.join(new_id)
        FileUtils.mkdir_p(id_tmp_dir)

        # Prepare firmware
        if options[:firmware]
          FileUtils.cp(options[:firmware], id_dir.join("firmware.fd"))
          FileUtils.cp(options[:efi_vars], id_dir.join("efi-vars.fd"))
          FileUtils.chmod(0644, id_dir.join("efi-vars.fd"))
        elsif options[:arch] == "aarch64" && !options[:firmware_format].nil?
          FileUtils.cp(options[:qemu_dir].join("edk2-aarch64-code.fd"), id_dir.join("edk2-aarch64-code.fd"))
          FileUtils.cp(options[:qemu_dir].join("edk2-arm-vars.fd"), id_dir.join("edk2-arm-vars.fd"))
          FileUtils.chmod(0644, id_dir.join("edk2-arm-vars.fd"))
        end

        # Create image
        options[:image_path].each_with_index do |img, i|
          suffix_index = i > 0 ? "-#{i}" : ''

          linked_image = id_dir.join("linked-box#{suffix_index}.img").to_s
          args = ["create", "-f", "qcow2", "-F", "qcow2", "-b", img.to_s]

          if !options[:extra_image_opts].nil?
            options[:extra_image_opts].each do |opt|
              args.push("-o")
              args.push(opt)
            end
          end

          args.push(linked_image)

          if i == 0
            if !options[:disk_resize].nil?
              args.push(options[:disk_resize])
            end
          end

          execute("qemu-img",  *args)
        end

        server = {
          :id => new_id,
        }
      end

      def created?
        result = @data_dir.join(@vm_id).directory?
      end

      def running?
        pid = process_id
        return false unless pid
        return windows_running?(pid) if windows?

        begin
          Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        end
      end

      def execute(*cmd, **opts, &block)
        if opts[:detach] && windows?
          dir = @tmp_dir.join(@vm_id)
          FileUtils.rm_f(dir.join("qemu.pid"))
          [local_socket('monitor'), local_socket('serial')].each { |path| FileUtils.rm_f(path) }
          pid = Process.spawn(*cmd, in: File::NULL, out: dir.join("qemu.stdout.log").to_s, err: dir.join("qemu.stderr.log").to_s, new_pgroup: true, close_others: true)
          50.times do
            return "" if process_id == pid && running?
            sleep 0.1
          end
          Process.kill("KILL", pid) rescue Errno::ESRCH
          raise Errors::ExecuteError, command: cmd.inspect, stderr: File.read(dir.join("qemu.stderr.log")), stdout: File.read(dir.join("qemu.stdout.log"))
        end
        result = nil
        interrupted = false

        if opts && opts[:detach]
          # give it some time to startup
          timeout = 5

          # edit version of "Subprocess.execute" for detach
          workdir = Dir.pwd
          process = ChildProcess.build(*cmd)

          stdout, stdout_writer = ::IO.pipe
          stderr, stderr_writer = ::IO.pipe
          process.io.stdout = stdout_writer
          process.io.stderr = stderr_writer

          process.leader = true
          process.detach = true

          ::Vagrant::Util::SafeChdir.safe_chdir(workdir) do
            process.start
          end

          if RUBY_PLATFORM != "java"
            stdout_writer.close
            stderr_writer.close
          end

          io_data = { stdout: "", stderr: "" }
          start_time = Time.now.to_i
          open_readers = [stdout, stderr]

          while true
            results = ::IO.select(open_readers, nil, nil, 0.1)
            results ||= []
            readers = results[0]

            # Check if we have exceeded our timeout
            break if (Time.now.to_i - start_time) > timeout

            if readers && !readers.empty?
              readers.each do |r|
                data = ::Vagrant::Util::IO.read_until_block(r)
                next if data.empty?

                io_name = r == stdout ? :stdout : :stderr
                io_data[io_name] += data
              end
            end

            break if process.exited?
          end

          if RUBY_PLATFORM == "java"
            stdout_writer.close
            stderr_writer.close
          end

          exit_code = process.exited? ? process.exit_code : 0
          result = ::Vagrant::Util::Subprocess::Result.new(exit_code, io_data[:stdout], io_data[:stderr])
        else
          # Append in the options for subprocess
          cmd << { notify: [:stdout, :stderr, :stdin] }

          interrupted  = false
          int_callback = ->{ interrupted = true }
          result = ::Vagrant::Util::Busy.busy(int_callback) do
            ::Vagrant::Util::Subprocess.execute(*cmd, &block)
          end
        end

        result.stderr.gsub!("\r\n", "\n")
        result.stdout.gsub!("\r\n", "\n")

        if result.exit_code != 0 && !interrupted
          raise Errors::ExecuteError,
            command: cmd.inspect,
            stderr: result.stderr,
            stdout: result.stdout
        end

        if opts
          if opts[:with_stderr]
            return result.stdout + " " + result.stderr
          else
            return result.stdout
          end
        end
      end

      # Vagrant's Disk middleware always passes the *complete* current disk
      # list and re-runs on every action_start (including a same-process
      # reload, which reuses this Driver instance) -- so attach_disk/attach_dvd
      # must be rebuilt from a clean slate each time, not accumulated across calls.
      def reset_attached_drives!
        @attached_drives = {disk: [], floppy: [], dvd: []}
      end

      def attach_dvd(disk)
        @attached_drives[:dvd] << disk
      end

      def attach_disk(disk)
        @attached_drives[:disk] << disk
      end

      def disk_dir
          @data_dir.join(@vm_id)
      end

      # Ordered paths of the box's disk overlays, reconstructed by index to
      # match start/import (glob only counts; names rebuild by index so a
      # two-digit suffix can't sort ahead of a single digit).
      def box_disk_paths
        id_dir = disk_dir
        count = id_dir.glob("linked-box*.img").count
        (0...count).map do |i|
          suffix = i > 0 ? "-#{i}" : ""
          id_dir.join("linked-box#{suffix}.img")
        end
      end

      # Flatten a box disk overlay into a standalone qcow2 at dst. convert reads
      # the whole backing chain and writes a fresh file, so the source overlay
      # (the live VM disk) is never modified.
      def convert_box_disk(src, dst)
        execute("qemu-img", "convert", "-O", "qcow2", src.to_s, dst.to_s)
      end
    end
  end
end
