require "vagrant"

module VagrantPlugins
  module QEMU
    class Config < Vagrant.plugin("2", :config)
      attr_accessor :ssh_port
      attr_accessor :arch
      attr_accessor :machine
      attr_accessor :cpu
      attr_accessor :smp
      attr_accessor :memory
      attr_accessor :net_device
      attr_accessor :image_path
      attr_accessor :qemu_dir
      attr_accessor :accel

      def initialize
        @ssh_port = UNSET_VALUE
        @arch = UNSET_VALUE
        @machine = UNSET_VALUE
        @cpu = UNSET_VALUE
        @smp = UNSET_VALUE
        @memory = UNSET_VALUE
        @net_device = UNSET_VALUE
        @image_path = UNSET_VALUE
        @qemu_dir = UNSET_VALUE
        @accel = UNSET_VALUE
      end

      #-------------------------------------------------------------------
      # Internal methods.
      #-------------------------------------------------------------------

      def merge(other)
        super.tap do |result|
        end
      end

      def finalize!
        @ssh_port = 50022 if @ssh_port == UNSET_VALUE
        @arch = "aarch64" if @arch == UNSET_VALUE
        @machine = "virt,accel=hvf,highmem=on" if @machine == UNSET_VALUE
        @cpu = "host" if @cpu == UNSET_VALUE
        @smp = "2" if @smp == UNSET_VALUE
        @memory = "4G" if @memory == UNSET_VALUE
        @net_device = "virtio-net-device" if @net_device == UNSET_VALUE
        @image_path = nil if @image_path == UNSET_VALUE
        @qemu_dir = "/opt/homebrew/share/qemu" if @qemu_dir == UNSET_VALUE
        @accel = nil if @accel == UNSET_VALUE
      end

      def validate(machine)
        # errors = _detected_errors
        errors = []
        { "QEMU Provider" => errors }
      end
    end
  end
end
