require "fileutils"
require "tmpdir"
require "yaml"

require "vagrant/action/builtin/cloud_init_setup"

require_relative "../network"

module VagrantPlugins
  module QEMU
    module Action
      # Carries the cloud-init network-config for the advanced-network private
      # NIC into a NoCloud cidata seed. The ISO build is delegated to the
      # :create_iso host capability and the attach goes through the provider
      # disk capability (cap/disk.rb).
      #
      # NoCloud reads user-data, meta-data and network-config from a single
      # filesystem labelled "cidata"; two cidata volumes are ambiguous. So when
      # core CloudInitSetup (which runs earlier in the chain) has already built
      # a user-data seed, we rebuild that same ISO in place with network-config
      # added instead of attaching a second seed.
      class CloudInitNetwork
        # Disk name core Vagrant::Action::Builtin::CloudInitSetup gives its
        # user-data seed.
        CORE_SEED_DISK_NAME = "vagrant-cloud_init-disk".freeze

        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_qemu::action::cloud_init_network")
        end

        def call(env)
          machine = env[:machine]

          pn = machine.config.vm.networks
            .select { |t, _| t == :private_network }
            .map { |_, opts| opts }
            .first

          if machine.provider_config.advanced_network && pn && pn[:ip]
            existing = machine.config.vm.disks.find do |d|
              d.type == :dvd && d.name == CORE_SEED_DISK_NAME
            end

            if existing
              merge_into_seed(machine, env, pn, existing.file)
            else
              attach_network_seed(machine, env, pn)
            end
          end

          @app.call(env)
        end

        private

        # No core cloud-init seed: build our own network-only seed and attach
        # it as a fresh :dvd disk.
        def attach_network_seed(machine, env, pn)
          iso_path = build_seed(machine, env, pn,
            user_data: "#cloud-config\n",
            file_destination: machine.data_dir.join("vagrant-qemu-network.iso"))

          machine.config.vm.disk :dvd, file: iso_path.to_s, name: "vagrant-qemu-network-disk"
          machine.config.vm.disks.each do |d|
            d.finalize! if d.type == :dvd && d.file == iso_path.to_s
          end
          @logger.info("Attached cloud-init network seed ISO at #{iso_path}")
        end

        # Core CloudInitSetup already built a user-data seed and attached it.
        # Rebuild that same ISO in place, carrying both the user-data and our
        # network-config in one cidata volume. No second disk is registered.
        def merge_into_seed(machine, env, pn, iso_path)
          ud_cfgs = machine.config.vm.cloud_init_configs
            .select { |c| c.type == :user_data }
          setup = Vagrant::Action::Builtin::CloudInitSetup.new(->(_) {}, env)
          user_data = setup.setup_user_data(machine, env, ud_cfgs).to_s

          FileUtils.rm_f(iso_path)
          build_seed(machine, env, pn,
            user_data: user_data,
            file_destination: Pathname.new(iso_path))
          @logger.info("Merged cloud-init network seed into #{iso_path}")
        end

        # Write a NoCloud cidata seed (network-config + meta-data + user-data)
        # and build the ISO via the :create_iso host capability. Returns the
        # ISO path.
        def build_seed(machine, env, pn, user_data:, file_destination:)
          if !env[:env].host.capability?(:create_iso)
            raise Vagrant::Errors::CreateIsoHostCapNotFound
          end

          mac0, mac1 = Network.nic_macs(machine.id, pn)
          network_config = Network.build_network_config(
            mac0: mac0,
            mac1: mac1,
            ip: pn[:ip],
            netmask: pn[:netmask] || "255.255.255.0"
          )

          source_dir = Pathname.new(Dir.mktmpdir("vagrant-qemu-network-seed"))
          begin
            File.write(source_dir.join("network-config"), network_config)
            File.write(source_dir.join("meta-data"),
              { "instance-id" => "i-#{machine.id.to_s.split("-").join}" }.to_yaml)
            File.write(source_dir.join("user-data"), user_data)

            env[:env].host.capability(
              :create_iso,
              source_dir,
              file_destination: file_destination,
              volume_id: "cidata"
            )
          ensure
            FileUtils.remove_entry(source_dir)
          end
        end
      end
    end
  end
end
