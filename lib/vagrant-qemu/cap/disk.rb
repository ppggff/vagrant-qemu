require "log4r"
require "json"
require "vagrant/util/numeric"

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
          # Vagrant re-invokes this on every action_start (including a
          # same-process reload), always passing the complete current disk
          # list -- reset before the empty check so a disk removed from the
          # Vagrantfile doesn't leave a stale entry attached either.
          machine.provider.driver.reset_attached_drives!
          return {} if defined_disks.empty?

          configured_disks = {disk: [], floppy: [], dvd: []}
          defined_disks.each do |disk|
            @@logger.info("Disk: #{disk.to_yaml}")
            case disk.type
            when :disk
              disk_data = setup_disk(machine, disk)
              if !disk_data.empty?
                configured_disks[:disk] << disk_data
                machine.provider.driver.attach_disk(disk_data) unless disk.primary
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
          return setup_primary_disk(machine, disk) if disk.primary

          disk_dir = machine.provider.driver.disk_dir
          disk_path = disk_dir.join("#{disk.name}.#{disk.disk_ext}")

          disk_provider_config = disk.provider_config[:qemu] if disk.provider_config

          # configure_disks re-runs on every action_start (including a
          # same-process reload); qemu-img create truncates an existing file
          # unconditionally, so skip it once the disk already exists instead
          # of silently wiping it. Resizing an existing disk isn't handled.
          if !disk_path.file?
            args = ["create", "-f", "qcow2", disk_path.to_s, "#{disk.size}"]
            machine.provider.driver.execute("qemu-img", *args)
          end

          {UUID: disk.id, Name: disk.name, Path: disk_path.to_s, primary: !!disk.primary}
        end

        # The box's first overlay is already attached as disk0 by Driver#start.
        # A primary disk declaration resizes that disk; attaching a new blank
        # qcow2 would leave the guest's boot disk unchanged.
        def self.setup_primary_disk(machine, disk)
          driver = machine.provider.driver
          path = driver.box_disk_paths.first
          raise Errors::ConfigError, err: "Cannot resize primary disk: no box disk exists" if path.nil?

          size = disk.size.is_a?(Integer) ? disk.size : Vagrant::Util::Numeric.string_to_bytes(disk.size)
          raise Errors::ConfigError, err: "Primary disk size must be positive" unless size && size > 0

          # Earlier versions attached a primary declaration as a separate blank
          # disk under this name; it is no longer attached but may hold data.
          legacy = driver.disk_dir.join("#{disk.name}.#{disk.disk_ext}")
          if legacy.file?
            machine.ui.warn(I18n.t("vagrant_qemu.primary_disk_legacy_detached",
              name: disk.name, path: legacy.to_s))
          end

          info = JSON.parse(driver.execute("qemu-img", "info", "--output=json", path.to_s))
          current_size = info.fetch("virtual-size")
          # Never shrink: a smaller target (or reload) must preserve guest data.
          if size > current_size
            machine.ui.detail(I18n.t("vagrant_qemu.primary_disk_growing",
              name: disk.name, current_size: readable_disk_size(current_size),
              requested_size: readable_disk_size(size)))
            driver.execute("qemu-img", "resize", path.to_s, size.to_s)
          elsif size < current_size
            machine.ui.warn(I18n.t("vagrant_qemu.primary_disk_shrink_not_supported",
              name: disk.name, current_size: readable_disk_size(current_size),
              requested_size: readable_disk_size(size)))
          end
          {UUID: disk.id, Name: disk.name, Path: path.to_s, primary: true}
        end

        def self.readable_disk_size(bytes)
          # Vagrant scales by 1024; use binary unit names to make that explicit.
          Vagrant::Util::Numeric.bytes_to_string(bytes).sub(/([KMGTPE])B\z/, ' \1iB')
        end
        private_class_method :readable_disk_size

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
