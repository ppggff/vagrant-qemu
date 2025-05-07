require "log4r"
require "open3"
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
          image_path = Array.new
          if env[:machine].provider_config.image_path
            paths = env[:machine].provider_config.image_path
            paths = [paths] if !paths.kind_of?(Array)
            paths.each do |p|
              image_path.append(Pathname.new(p))
            end
          else
            disks = env[:machine].box.metadata.fetch('disks', [])
            if disks.empty?
              # box v1 format
              image_path.append(env[:machine].box.directory.join("box.img"))
            else
              # box v2 format
              disks.each_with_index do |d, i|
                if d['path'].nil?
                  @logger.error("Missing box image path for disk #{i}")
                  raise Errors::BoxInvalid, name: env[:machine].name, err: "Missing box image path for disk #{i}"
                end
                image_path.append(env[:machine].box.directory.join(d['path']))
              end
            end
          end

          if image_path.empty?
            @logger.error("Empty box image path")
            raise Errors::BoxInvalid, name: env[:machine].name, err: "Empty box image path"
          end
          image_path.each do |img|
            if !img.file?
              @logger.error("Invalid box image path: #{img}")
              raise Errors::BoxInvalid, name: env[:machine].name, err: "Invalid box image path: #{img}"
            end
            img_str = img.to_s
            stdout, stderr, status = Open3.capture3('qemu-img', 'info', '--output=json', img_str)
            if !status.success?
              @logger.error("Run qemu-img info failed, #{img_str}, out: #{stdout}, err: #{stderr}")
              raise Errors::BoxInvalid, name: env[:machine].name, err: "Run qemu-img info failed, #{img_str}, out: #{stdout}, err: #{stderr}"
            end
            img_info = JSON.parse(stdout)
            format = img_info['format']
            if format != 'qcow2'
              @logger.error("Invalid box image format, #{img_str}, format: #{format}")
              raise Errors::BoxInvalid, name: env[:machine].name, err: "Invalid box image format, #{img_str}, format: #{format}"
            end
            @logger.info("Found box image path: #{img_info}")
          end

          qemu_dir = Pathname.new(env[:machine].provider_config.qemu_dir)
          if !qemu_dir.directory?
            @logger.error("Invalid qemu dir: #{qemu_dir}")
            raise Errors::ConfigError, err: "Invalid qemu dir: #{qemu_dir}"
          else
            @logger.info("Found qemu dir: #{qemu_dir}")
          end

          env[:ui].output("Importing a QEMU instance")

          options = {
            :image_path => image_path,
            :qemu_dir => qemu_dir,
            :arch => env[:machine].provider_config.arch,
            :firmware_format => env[:machine].provider_config.firmware_format,
            :extra_image_opts => env[:machine].provider_config.extra_image_opts,
            :disk_resize => env[:machine].provider_config.disk_resize,
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
