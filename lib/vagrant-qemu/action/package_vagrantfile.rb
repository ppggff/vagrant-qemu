require "pathname"

module VagrantPlugins
  module QEMU
    module Action
      # Writes a minimal default Vagrantfile into the box declaring only the
      # architecture, so a consumer on a different host arch doesn't default to
      # the wrong one. Networking, MAC and host-specific machine flags are left
      # out on purpose — they are environment-specific and come from the
      # consuming Vagrantfile. The core Package middleware appends the SSH
      # private-key config to this same file afterwards.
      class PackageVagrantfile
        def initialize(app, env)
          @app = app
        end

        def call(env)
          @env = env
          create_vagrantfile
          @app.call(env)
        end

        def create_vagrantfile
          arch = @env[:machine].provider_config.arch
          path = Pathname.new(@env["export.temp_dir"]).join("Vagrantfile")
          File.write(path, <<~VF)
            Vagrant.configure("2") do |config|
              config.vm.provider :qemu do |qe|
                qe.arch = "#{arch}"
              end
            end
          VF
        end
      end
    end
  end
end
