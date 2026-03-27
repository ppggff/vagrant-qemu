module VagrantPlugins
  module QEMU
    module Action
      class Destroy
        def initialize(app, env)
          @app = app
        end

        def call(env)
          env[:ui].info(I18n.t("vagrant_qemu.destroying"))
          begin
            env[:machine].provider.driver.delete
          rescue => e
            raise Errors::VagrantQEMUError,
              "Failed to delete VM files: #{e.message}. Machine ID preserved."
          end
          env[:machine].id = nil

          @app.call(env)
        end
      end
    end
  end
end
