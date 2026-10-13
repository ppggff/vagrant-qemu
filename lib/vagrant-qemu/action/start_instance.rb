require "log4r"

module VagrantPlugins
  module QEMU
    module Action
      # This starts a stopped instance.
      class StartInstance
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_qemu::action::start_instance")
          @start_completed = false
        end

        def call(env)
          @start_completed = false
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
            :socket_vmnet_socket => config.socket_vmnet_socket,
            :socket_vmnet_client => config.socket_vmnet_client,
          }

          # Pick up SSH port that may have been corrected by HandleForwardedPortCollisions
          env[:machine].config.vm.networks.each do |type, opts|
            if !config.net_device.nil? && type == :forwarded_port && opts[:id] == "ssh" && !opts[:disabled]
              options[:ssh_port] = opts[:host]
              break
            end
          end

          # Collect private_network configs from Vagrantfile
          private_networks = env[:machine].config.vm.networks.select { |t, _| t == :private_network }
          options[:private_networks] = private_networks.map { |_, opts| opts }

          env[:ui].output(I18n.t("vagrant_qemu.starting"))
          env[:machine].provider.driver.start(options)
          @control_port = options[:control_port]
          @start_completed = true
          result = @app.call(env)
          @start_completed = false
          result
        end

        # Warden calls recover with the original failure. Stop only instances
        # successfully launched by this action whose communicator never booted.
        def recover(env)
          return unless @start_completed
          error = env["vagrant.error"]
          return unless error.is_a?(Vagrant::Errors::VMBootTimeout) ||
            error.is_a?(Vagrant::Errors::VMBootBadState)

          @start_completed = false
          @logger.warn("Boot failed; stopping the QEMU instance")
          # The guest may not be able to handle ACPI yet. Ask QEMU to flush
          # and quit directly, giving it several seconds before SIGKILL.
          timeout = [[env[:machine].provider_config.graceful_timeout, 3].max, 10].min
          driver = env[:machine].provider.driver
          driver.stop(control_port: @control_port, graceful_timeout: timeout, quit_only: true)
          message = driver.running? ? "boot_failed_stop_failed" : "boot_failed_stopped"
          env[:ui].warn(I18n.t("vagrant_qemu.#{message}"))
        rescue StandardError => cleanup_error
          # Preserve the boot error that Warden is already propagating.
          @logger.warn("Could not stop QEMU after boot failure: #{cleanup_error}")
          env[:ui].warn(I18n.t("vagrant_qemu.boot_failed_stop_failed"))
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
