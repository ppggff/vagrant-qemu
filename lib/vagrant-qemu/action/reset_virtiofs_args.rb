require_relative "../synced_folder_virtiofs"

module VagrantPlugins
  module QEMU
    module Action
      class ResetVirtioFSArgs
        def initialize(app, env)
          @app = app
        end

        def call(env)
          machine = env[:machine]
          machine.provider_config.virtiofs_qemu_args = []
          SyncedFolderVirtioFS.new.cleanup(machine, {})
          @starting = true
          result = @app.call(env)
          @starting = false
          result
        end

        def recover(env)
          machine = env[:machine]
          return unless @starting && !machine.provider_config.virtiofs_qemu_args.empty?
          # Warden unwinds StartInstance first. Once its recovery stops QEMU,
          # the daemons can stop too. A running guest keeps its shares.
          return if machine.provider.driver.running?
          unless env[:virtiofs_logs_shown]
            Dir.glob(machine.data_dir.join("virtiofs/*.log")).each do |path|
              machine.ui.error("virtiofsd log (#{path}):\n#{File.read(path)}")
            end
          end
          SyncedFolderVirtioFS.new.cleanup(machine, preserve_logs: true)
          machine.provider_config.virtiofs_qemu_args = []
        rescue StandardError => error
          machine.ui.error("VirtioFS recovery failed: #{error.message}")
        end
      end
    end
  end
end
