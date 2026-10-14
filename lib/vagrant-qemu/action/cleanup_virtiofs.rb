require_relative "../synced_folder_virtiofs"

module VagrantPlugins
  module QEMU
    module Action
      class CleanupVirtioFS
        def initialize(app, env)
          @app = app
        end

        def call(env)
          SyncedFolderVirtioFS.new.cleanup(env[:machine], {})
          @app.call(env)
        end
      end
    end
  end
end
