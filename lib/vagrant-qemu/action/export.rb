require "json"
require "open3"
require "pathname"
require "log4r"

module VagrantPlugins
  module QEMU
    module Action
      # Produces the box's disk artifacts and metadata.json in export.temp_dir:
      # flattens each box-disk overlay into a standalone qcow2 and describes them
      # in a libvirt-format metadata.json. Only the VM's box disks are packaged;
      # additional disks, DVDs and cloud-init seed ISOs are left out.
      class Export
        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_qemu::action::export")
        end

        def call(env)
          @env = env

          if env[:machine].state.id != :stopped
            raise Vagrant::Errors::VMPowerOffToPackage
          end

          export
          @app.call(env)
        end

        def export
          driver   = @env[:machine].provider.driver
          temp_dir = Pathname.new(@env["export.temp_dir"])
          disks    = driver.box_disk_paths

          if disks.empty?
            raise Errors::BoxInvalid, name: @env[:machine].name, err: "No box disk found to package"
          end

          multi     = disks.size > 1
          disk_meta = []
          disks.each_with_index do |src, i|
            name = multi ? "box_#{i + 1}.img" : "box.img"
            @env[:ui].info(I18n.t("vagrant_qemu.packaging_disk", name: name))
            driver.convert_box_disk(src, temp_dir.join(name))
            disk_meta << { "path" => name }
          end

          write_metadata(temp_dir, disk_meta, multi)
        end

        # libvirt box metadata: provider must be "libvirt" (the provider's
        # box_format) or the packaged box won't match on `box add`.
        def write_metadata(temp_dir, disk_meta, multi)
          metadata = {
            "provider"     => "libvirt",
            "format"       => "qcow2",
            "virtual_size" => virtual_size_gb(temp_dir.join(disk_meta.first["path"])),
          }
          metadata["disks"] = disk_meta if multi
          File.write(temp_dir.join("metadata.json"), JSON.pretty_generate(metadata))
        end

        def virtual_size_gb(img)
          stdout, stderr, status = Open3.capture3("qemu-img", "info", "--output=json", img.to_s)
          if !status.success?
            raise Errors::ExecuteError, command: "qemu-img info", stderr: stderr, stdout: stdout
          end
          bytes = JSON.parse(stdout)["virtual-size"]
          (bytes.to_f / (1024**3)).ceil
        end
      end
    end
  end
end
