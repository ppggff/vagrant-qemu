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
            # Vagrant errors only render error_key translations; a bare
            # String here would be silently dropped.
            raise Errors::DestroyError, message: e.message
          end
          env[:machine].id = nil

          @app.call(env)
        end
      end
    end
  end
end
