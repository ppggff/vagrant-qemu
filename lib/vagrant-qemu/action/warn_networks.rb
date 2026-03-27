require_relative "../network"

module VagrantPlugins
  module QEMU
    module Action
      class WarnNetworks
        def initialize(app, env)
          @app = app
        end

        def call(env)
          private_networks = env[:machine].config.vm.networks.select { |t, _| t == :private_network }

          if !private_networks.empty?
            if env[:machine].provider_config.advanced_network
              env[:ui].info(I18n.t("vagrant_qemu.advanced_network_enabled"))
            else
              env[:ui].warn(I18n.t("vagrant_qemu.warn_networks_need_advanced"))
            end
          end

          @app.call(env)
        end
      end
    end
  end
end
