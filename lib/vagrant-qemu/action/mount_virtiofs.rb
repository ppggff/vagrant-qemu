require "log4r"
require "json"
require "shellwords"

module VagrantPlugins
  module QEMU
    module Action
      class MountVirtioFS
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_qemu::action::mount_virtiofs")
        end

        def call(env)
          machine = env[:machine]

          # prepare sees Vagrant's resolved folder types. Use precisely that
          # mapping, including shares selected through allowed_synced_folder_types.
          mounts_file = machine.data_dir.join("virtiofs", "mounts.json")
          if !machine.provider_config.virtiofs_qemu_args.empty? && mounts_file.file?
            JSON.parse(File.read(mounts_file)).each do |tag, guestpath|

              escaped_guestpath = Shellwords.escape(guestpath)
              machine.communicate.sudo("mkdir -p #{escaped_guestpath}")
              machine.communicate.sudo("mount -t virtiofs #{Shellwords.escape(tag)} #{escaped_guestpath}")
              machine.ui.info("Mounted virtiofs #{tag} at #{guestpath}")
            end
          end

          @app.call(env)
        end
      end
    end
  end
end
