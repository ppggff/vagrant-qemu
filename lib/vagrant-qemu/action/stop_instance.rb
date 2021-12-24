module VagrantPlugins
  module QEMU
    module Action
      # This stops the running instance.
      class StopInstance
        def initialize(app, env)
          @app = app
        end

        def call(env)
          env[:ui].info(I18n.t("vagrant_qemu.stopping"))
          env[:machine].provider.driver.stop
          @app.call(env)
        end
    end
  end
end
