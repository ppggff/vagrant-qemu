require "log4r"

module VagrantPlugins
  module QEMU
    module Cap
      module Disk
        @@logger = Log4r::Logger.new("vagrant_qemu::cap::disk")

        DEFAULT_DISK_EXT_LIST = ["qcow2", "iso"].map(&:freeze).freeze
        DEFAULT_DISK_EXT = "qcow2".freeze

        # @param [Vagrant::Machine] machine
        # @return [String]
        def self.set_default_disk_ext(machine)
          DEFAULT_DISK_EXT
        end

        # @param [Vagrant::Machine] machine
        # @return [Array]
        def self.default_disk_exts(machine)
          DEFAULT_DISK_EXT_LIST
        end

        # @param [Vagrant::Machine] machine
        # @param [String] disk_ext
        # @return [Bool]
        def self.validate_disk_ext(machine, disk_ext)
          DEFAULT_DISK_EXT_LIST.include?(disk_ext)
        end

        # @param [Vagrant::Machine] machine
        # @param [VagrantPlugins::Kernel_V2::VagrantConfigDisk] defined_disks
        # @return [Hash] configured_disks - A hash of all the current configured disks
        def self.configure_disks(machine, defined_disks)
          return {} if defined_disks.empty?

          configured_disks = {disk: [], floppy: [], dvd: []}
          defined_disks.each do |disk|
            @@logger.info("Disk: #{disk.to_yaml}")
            case disk.type
            when :disk
              disk_data = setup_disk(machine, disk)
              if !disk_data.empty?
                configured_disks[:disk] << disk_data
                machine.provider.driver.attach_disk(disk_data)
              end
            when :floppy
              machine.ui.info(I18n.t("vagrant_qemu.errors.floppy_unsupported"))
            when :dvd
              disk_data = setup_dvd(machine, disk)
              if !disk_data.empty?
                configured_disks[:dvd] << disk_data
                machine.provider.driver.attach_dvd(disk_data)
              end
            else
              @@logger.info("unsupported disk type: #{disk.type}")
            end
          end

          configured_disks
        end

        # @param [Vagrant::Machine] machine
        # @param [VagrantPlugins::Kernel_V2::VagrantConfigDisk] defined_disks
        # @param [Hash] disk_meta - A hash of all the previously defined disks
        #                           from the last configure_disk action
        # @return [nil]
        def self.cleanup_disks(machine, defined_disks, disk_meta)
          return if disk_meta.values.flatten.empty?
        end

        protected

        # Sets up all disk configs of type `:disk`
        #
        # @param [Vagrant::Machine] machine - the current machine
        # @param [Config::Disk] disk - the current disk to configure
        # @return [Hash] - disk_metadata
        def self.setup_disk(machine, disk)
          disk_dir = machine.provider.driver.disk_dir
          disk_path = disk_dir.join("#{disk.name}.#{disk.disk_ext}")
          args = ["create", "-f", "qcow2"]

          disk_provider_config = disk.provider_config[:qemu] if disk.provider_config
          args.push(disk_path.to_s)
          args.push("#{disk.size}")
          machine.provider.driver.execute("qemu-img", *args)

          {UUID: disk.id, Name: disk.name, Path: disk_path.to_s, primary: !!disk.primary}
        end

        # Sets up all disk configs of type `:dvd`
        #
        # @param [Vagrant::Machine] machine - the current machine
        # @param [Config::Disk] disk - the current disk to configure
        # @return [Hash] - disk_metadata
        def self.setup_dvd(machine, disk)
          {UUID: disk.id, Name: disk.name, Path: disk.file, primary: !!disk.primary}
        end

      end
    end
  end
end
