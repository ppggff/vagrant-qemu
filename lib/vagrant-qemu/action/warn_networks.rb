module VagrantPlugins
  module QEMU
    module Action
      class WarnNetworks
        def initialize(app, env)
          @app = app
        end

        def call(env)
          if env[:machine].config.vm.networks.length > 0
            env[:ui].warn(I18n.t("vagrant_qemu.warn_networks"))
          end

          @app.call(env)
        end
      end
    end
  end
end
