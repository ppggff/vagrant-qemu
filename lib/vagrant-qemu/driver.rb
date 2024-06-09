require 'childprocess'
require 'securerandom'

require "vagrant/util/busy"
require 'vagrant/util/io'
require "vagrant/util/safe_chdir"
require "vagrant/util/subprocess"

require_relative "plugin"

module VagrantPlugins
  module QEMU
	  class Driver
      # @return [String] VM ID
      attr_reader :vm_id
      attr_reader :data_dir
      attr_reader :tmp_dir

      def initialize(id, dir, tmp)
        @vm_id = id
        @data_dir = dir
        @tmp_dir = tmp.join("vagrant-qemu")
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
          pid_file = id_dir.join("qemu.pid").to_s

          image_path = Array.new
          image_count = id_dir.glob("linked-box*.img").count
          for i in 0..image_count-1 do
            suffix_index = i > 0 ? "-#{i}" : ''
            image_path.append(id_dir.join("linked-box#{suffix_index}.img").to_s)
          end

          id_tmp_dir = @tmp_dir.join(@vm_id)
          FileUtils.mkdir_p(id_tmp_dir)

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
          cmd += %W(qemu-system-#{options[:arch]})

          # basic
          cmd += %W(-machine #{options[:machine]}) if !options[:machine].nil?
          cmd += %W(-cpu #{options[:cpu]}) if !options[:cpu].nil?
          cmd += %W(-smp #{options[:smp]}) if !options[:smp].nil?
          cmd += %W(-m #{options[:memory]}) if !options[:memory].nil?

          # network
          if !options[:net_device].nil?
            # net device
            macaddr = options[:mac_address].nil? ? "" : ",mac=" + options[:mac_address]
            cmd += %W(-device #{options[:net_device]},netdev=net0#{macaddr})

            # net type
            net_type = "user"
            if !options[:socket_fd].nil?
              net_type = "socket,fd=#{options[:socket_fd]}"
            end

            # ports
            hostfwd = ""
            if options[:socket_fd].nil?
              hostfwd = ",hostfwd=tcp::#{options[:ssh_port]}-:22"
              options[:ports].each do |v|
                hostfwd += ",hostfwd=#{v}"
              end
            end
            extra_netdev = ""
            if !options[:extra_netdev_args].nil?
              extra_netdev = ",#{options[:extra_netdev_args]}"
            end
            cmd += %W(-netdev #{net_type},id=net0#{hostfwd}#{extra_netdev})
          end

          # drive
          if !options[:drive_interface].nil?
            image_path.each do |img|
              cmd += %W(-drive if=#{options[:drive_interface]},format=qcow2,file=#{img})
            end
          end
          if options[:arch] == "aarch64" && !options[:firmware_format].nil?
            fm1_path = id_dir.join("edk2-aarch64-code.fd").to_s
            fm2_path = id_dir.join("edk2-arm-vars.fd").to_s
            cmd += %W(-drive if=pflash,format=#{options[:firmware_format]},file=#{fm1_path},readonly=on)
            cmd += %W(-drive if=pflash,format=#{options[:firmware_format]},file=#{fm2_path})
          end

          # control
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
          if !options[:control_port].nil?
            Socket.tcp("localhost", options[:control_port], connect_timeout: 5) do |sock|
              sock.print "system_powerdown\n"
              sock.close_write
              sock.read
            end
          else
            id_tmp_dir = @tmp_dir.join(@vm_id)
            unix_socket_path = id_tmp_dir.join("qemu_socket").to_s
            Socket.unix(unix_socket_path) do |sock|
              sock.print "system_powerdown\n"
              sock.close_write
              sock.read
            end
         end
        end
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
          execute("qemu-img", "create", "-f", "qcow2", "-F", "qcow2", "-b", img.to_s, id_dir.join("linked-box#{suffix_index}.img").to_s)
        end

        server = {
          :id => new_id,
        }
      end

      def created?
        result = @data_dir.join(@vm_id).directory?
      end

      def running?
        pid_file = @data_dir.join(@vm_id).join("qemu.pid")
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
            return if (Time.now.to_i - start_time) > timeout

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

          result = ::Vagrant::Util::Subprocess::Result.new(process.exit_code, io_data[:stdout], io_data[:stderr])
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
    end
  end
end
