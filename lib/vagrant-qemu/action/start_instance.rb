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
          }

          env[:ui].output(I18n.t("vagrant_qemu.starting"))
          env[:machine].provider.driver.start(options)
          @app.call(env)
        end
      end
    end
  end
end
