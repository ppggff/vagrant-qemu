require 'log4r'
require 'childprocess'
require 'securerandom'
require 'yaml'

require "vagrant/util/busy"
require 'vagrant/util/io'
require "vagrant/util/safe_chdir"
require "vagrant/util/subprocess"
require "vagrant/util/which"

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
        if created?
          id_dir = @data_dir.join(@vm_id)
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
              cmd += %W(#{options[:qemu_bin]})
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
          if !options[:net_device].nil?
            private_networks = options[:private_networks] || []
            use_advanced = options[:advanced_network] && !private_networks.empty?

            if use_advanced
              # Dual-NIC: NIC 0 = user-mode (SSH + port forwarding), NIC 1 = advanced backend
              pn = private_networks.first
              mac0, mac1 = Network.nic_macs(@vm_id, pn)

              # NIC 0: user-mode
              cmd += %W(-device #{options[:net_device]},netdev=net0,mac=#{mac0})
              hostfwd = "hostfwd=tcp::#{options[:ssh_port]}-:22"
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
              cmd += %W(-device #{options[:net_device]},netdev=net1,mac=#{mac1})
              cmd += backend.build_netdev_args("net1", options)
            else
              # Single NIC: user-mode only (original behavior, no cloud-init)
              cmd += %W(-device #{options[:net_device]},netdev=net0)

              hostfwd = "hostfwd=tcp::#{options[:ssh_port]}-:22"
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
          if options[:arch] == "aarch64" && !options[:firmware_format].nil?
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
          cmd += %W(-chardev socket,id=mon0,#{control_socket},server=on,wait=off)
          cmd += %W(-mon chardev=mon0,mode=readline)
          cmd += %W(-chardev socket,id=ser0,#{debug_socket},server=on,wait=off)
          cmd += %W(-serial chardev:ser0)
          cmd += %W(-pidfile #{pid_file})
          if !options[:no_daemonize]
            cmd += %W(-daemonize)
          end

          # other default
          cmd += options[:other_default]

          # user-defined
          cmd += options[:extra_qemu_args]

          opts = {:detach => options[:no_daemonize]}
          execute(*cmd, **opts)
        end
      end

      def stop(options)
        if running?
          send_powerdown(with_persisted_control_port(options))
          wait_for_shutdown(options[:graceful_timeout] || 60)
        end
      end

      private

      # Prefer the control_port the VM was actually started with (persisted
      # in options.yml) so halt still works after a Vagrantfile edit.
      def with_persisted_control_port(options)
        options_file = @tmp_dir.join(@vm_id).join("options.yml")
        return options if !options_file.file?

        persisted = YAML.safe_load(File.read(options_file), permitted_classes: [Symbol]) rescue nil
        return options if persisted.nil? || !persisted.key?(:control_port)

        options.merge(:control_port => persisted[:control_port])
      end

      def send_powerdown(options)
        if !options[:control_port].nil?
          Socket.tcp("localhost", options[:control_port], connect_timeout: 5) do |sock|
            sock.print "system_powerdown\n"
            sock.close_write
            sock.read rescue nil
          end
        else
          id_tmp_dir = @tmp_dir.join(@vm_id)
          unix_socket_path = id_tmp_dir.join("qemu_socket").to_s
          Socket.unix(unix_socket_path) do |sock|
            sock.print "system_powerdown\n"
            sock.close_write
            sock.read rescue nil
          end
        end
      end

      def wait_for_shutdown(timeout)
        timeout.times do
          return unless running?
          sleep 1
        end

        # Still running after timeout, force kill
        if running?
          @logger.warn("VM did not shut down within #{timeout}s, forcing kill")
          force_kill
        end
      end

      def force_kill
        pid_file = @tmp_dir.join(@vm_id).join("qemu.pid")
        return unless pid_file.file?

        pid = File.read(pid_file).to_i
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
        if options[:arch] == "aarch64" && !options[:firmware_format].nil?
          execute("cp", options[:qemu_dir].join("edk2-aarch64-code.fd").to_s, id_dir.join("edk2-aarch64-code.fd").to_s)
          execute("cp", options[:qemu_dir].join("edk2-arm-vars.fd").to_s, id_dir.join("edk2-arm-vars.fd").to_s)
          execute("chmod", "644", id_dir.join("edk2-arm-vars.fd").to_s)
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
        pid_file = @tmp_dir.join(@vm_id).join("qemu.pid")
        return false if !pid_file.file?

        begin
          Process.kill(0, File.read(pid_file).to_i)
          true
        rescue Errno::ESRCH
          false
        end
      end

      def execute(*cmd, **opts, &block)
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

      def attach_dvd(disk)
        @attached_drives[:dvd] << disk
      end

      def attach_disk(disk)
        @attached_drives[:disk] << disk
      end

      def disk_dir
          @data_dir.join(@vm_id)
      end
    end
  end
end
