require "log4r"

module VagrantPlugins
  module QEMU
    module Action
      # This starts a stopped instance.
      class StartInstance
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_qemu::action::start_instance")
        end

        def call(env)
          fw_ports = forwarded_ports(env)
          config = env[:machine].provider_config

          options = {
            :ssh_host => config.ssh_host,
            :ssh_port => config.ssh_port,
            :arch => config.arch,
            :machine => config.machine,
            :cpu => config.cpu,
            :smp => config.smp,
            :memory => config.memory,
            :net_device => config.net_device,
            :drive_interface => config.drive_interface,
            :qemu_bin => config.qemu_bin,
            :extra_qemu_args => config.extra_qemu_args,
            :extra_netdev_args => config.extra_netdev_args,
            :extra_drive_args => config.extra_drive_args,
            :ports => fw_ports,
            :control_port => config.control_port,
            :debug_port => config.debug_port,
            :no_daemonize => config.no_daemonize,
            :firmware_format => config.firmware_format,
            :other_default => config.other_default,
            :extra_image_opts => config.extra_image_opts,
            # Advanced networking
            :advanced_network => config.advanced_network,
            :net_mode => config.net_mode,
            :vmnet_interface => config.vmnet_interface,
            :tap_device => config.tap_device,
            :mcast_addr => config.mcast_addr,
            :socket_opts => config.socket_opts,
          }

          # Pick up SSH port that may have been corrected by HandleForwardedPortCollisions
          env[:machine].config.vm.networks.each do |type, opts|
            if type == :forwarded_port && opts[:id] == "ssh"
              options[:ssh_port] = opts[:host]
              break
            end
          end

          # Collect private_network configs from Vagrantfile
          private_networks = env[:machine].config.vm.networks.select { |t, _| t == :private_network }
          options[:private_networks] = private_networks.map { |_, opts| opts }

          env[:ui].output(I18n.t("vagrant_qemu.starting"))
          env[:machine].provider.driver.start(options)
          @app.call(env)
        end

        def forwarded_ports(env)
          result = []

          env[:machine].config.vm.networks.each do |type, options|
            next if type != :forwarded_port

            # SSH port is handled by PrepareForwardedPortCollisionParams
            next if options[:id] == "ssh"

            # Skip port if it is disabled
            next if options[:disabled]

            result.push("#{options[:protocol]}:#{options[:host_ip]}:#{options[:host]}-#{options[:guest_ip]}:#{options[:guest]}")
          end

          result
        end
      end
    end
  end
end
