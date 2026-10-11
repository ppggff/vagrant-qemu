module VagrantPlugins
  module QEMU
    module Action
      class ResetVirtioFSArgs
        def initialize(app, env)
          @app = app
        end

        def call(env)
          env[:machine].provider_config.virtiofs_qemu_args = []
          @app.call(env)
        end
      end
    end
  end
end
