require "vagrant"

module VagrantPlugins
  module QEMU
    class Config < Vagrant.plugin("2", :config)
      attr_accessor :ssh_host
      attr_accessor :ssh_port
      attr_accessor :arch
      attr_accessor :machine
      attr_accessor :cpu
      attr_accessor :smp
      attr_accessor :memory
      attr_accessor :net_device
      attr_accessor :mac_address
      attr_accessor :socket_fd
      attr_accessor :drive_interface
      attr_accessor :image_path
      attr_accessor :qemu_dir
      attr_accessor :extra_qemu_args
      attr_accessor :extra_netdev_args
      attr_accessor :control_port
      attr_accessor :debug_port
      attr_accessor :no_daemonize
      attr_accessor :firmware_format
      attr_accessor :other_default

      def initialize
        @ssh_host = UNSET_VALUE
        @ssh_port = UNSET_VALUE
        @arch = UNSET_VALUE
        @machine = UNSET_VALUE
        @cpu = UNSET_VALUE
        @smp = UNSET_VALUE
        @memory = UNSET_VALUE
        @net_device = UNSET_VALUE
        @mac_address = UNSET_VALUE
        @socket_fd = UNSET_VALUE
        @drive_interface = UNSET_VALUE
        @image_path = UNSET_VALUE
        @qemu_dir = UNSET_VALUE
        @extra_qemu_args = UNSET_VALUE
        @extra_netdev_args = UNSET_VALUE
        @control_port = UNSET_VALUE
        @debug_port = UNSET_VALUE
        @no_daemonize = UNSET_VALUE
        @firmware_format = UNSET_VALUE
        @other_default = UNSET_VALUE
      end

      #-------------------------------------------------------------------
      # Internal methods.
      #-------------------------------------------------------------------

      def merge(other)
        super.tap do |result|
        end
      end

      def finalize!
        @ssh_host = "127.0.0.1" if @ssh_host == UNSET_VALUE
        @ssh_port = 50022 if @ssh_port == UNSET_VALUE
        @arch = "aarch64" if @arch == UNSET_VALUE
        @machine = "virt,accel=hvf,highmem=on" if @machine == UNSET_VALUE
        @cpu = "host" if @cpu == UNSET_VALUE
        @smp = "2" if @smp == UNSET_VALUE
        @memory = "4G" if @memory == UNSET_VALUE
        @net_device = "virtio-net-device" if @net_device == UNSET_VALUE
        @mac_address = nil if @mac_address == UNSET_VALUE
        @socket_fd = nil if @socket_fd == UNSET_VALUE
        @drive_interface = "virtio" if @drive_interface == UNSET_VALUE
        @image_path = nil if @image_path == UNSET_VALUE
        @qemu_dir = "/opt/homebrew/share/qemu" if @qemu_dir == UNSET_VALUE
        @extra_qemu_args = [] if @extra_qemu_args == UNSET_VALUE
        @extra_netdev_args = nil if @extra_netdev_args == UNSET_VALUE
        @control_port = nil if @control_port == UNSET_VALUE
        @debug_port = nil if @debug_port == UNSET_VALUE
        @no_daemonize = false if @no_daemonize == UNSET_VALUE
        @firmware_format = "raw" if @firmware_format == UNSET_VALUE
        @other_default = %W(-parallel null -monitor none -display none -vga none) if @other_default == UNSET_VALUE
      end

      def validate(machine)
        # errors = _detected_errors
        errors = []
        { "QEMU Provider" => errors }
      end
    end
  end
end
