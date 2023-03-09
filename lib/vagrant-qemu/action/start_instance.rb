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
          options = {
            :ssh_port => env[:machine].provider_config.ssh_port,
            :arch => env[:machine].provider_config.arch,
            :machine => env[:machine].provider_config.machine,
            :cpu => env[:machine].provider_config.cpu,
            :smp => env[:machine].provider_config.smp,
            :memory => env[:machine].provider_config.memory,
            :net_device => env[:machine].provider_config.net_device,
            :drive_interface => env[:machine].provider_config.drive_interface,
            :extra_qemu_args => env[:machine].provider_config.extra_qemu_args,
            :extra_netdev_args => env[:machine].provider_config.extra_netdev_args,
            :ports => forwarded_ports(env),
            :control_port => env[:machine].provider_config.control_port,
            :debug_port => env[:machine].provider_config.debug_port,
            :no_daemonize => env[:machine].provider_config.no_daemonize
          }

          env[:ui].output(I18n.t("vagrant_qemu.starting"))
          env[:machine].provider.driver.start(options)
          @app.call(env)
        end

        def forwarded_ports(env)
          result = []

          env[:machine].config.vm.networks.each do |type, options|
            next if type != :forwarded_port

            # Don't include SSH
            next if options[:id] == "ssh"

            # Skip port if it is disabled
            next if options[:disabled]

            host_ip = ""
            host_ip = "#{options[:host_ip]}:" if options[:host_ip]
            guest_ip = ""
            guest_ip = "#{options[:guest_ip]}:" if options[:guest_ip]
            result.push("#{options[:protocol]}:#{host_ip}:#{options[:host]}-#{guest_ip}:#{options[:guest]}")
          end

          result
        end
      end
    end
  end
end
