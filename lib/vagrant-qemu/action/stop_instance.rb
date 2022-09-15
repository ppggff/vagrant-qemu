module VagrantPlugins
  module QEMU
    module Action
      # This stops the running instance.
      class StopInstance
        def initialize(app, env)
          @app = app
        end

        def call(env)
          options = {
            :control_port => env[:machine].provider_config.control_port
          }

          env[:ui].info(I18n.t("vagrant_qemu.stopping"))
          env[:machine].provider.driver.stop(options)
          @app.call(env)
        end
      end
    end
  end
end
