require "log4r"
require "pathname"

module VagrantPlugins
  module QEMU
    module Action
      class Import

        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_qemu::action::import")
        end

        def call(env)
          image_path = nil
          if env[:machine].provider_config.image_path
            image_path = Pathname.new(env[:machine].provider_config.image_path)
          elsif env[:machine].box
            image_path = env[:machine].box.directory.join("box.img")
          end

          if !image_path || !image_path.file?
            @logger.error("Invalid box image path: #{image_path}")
            raise Errors::BoxInvalid, name: env[:machine].name
          else
            @logger.info("Found box image path: #{image_path}")
          end

          qemu_dir = Pathname.new(env[:machine].provider_config.qemu_dir)
          if !qemu_dir.directory?
            @logger.error("Invalid qemu dir: #{qemu_dir}")
            raise Errors::BoxInvalid, name: env[:machine].name
          else
            @logger.info("Found qemu dir: #{qemu_dir}")
          end

          env[:ui].output("Importing a QEMU instance")

          options = {
            :image_path => image_path,
            :qemu_dir => qemu_dir,
          }

          env[:ui].detail("Creating and registering the VM...")
          server = env[:machine].provider.driver.import(options)

          env[:ui].detail("Successfully imported VM")
          env[:machine].id = server[:id]
          @app.call(env)
        end
      end
    end
  end
end
