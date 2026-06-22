require "vagrant"

module VagrantPlugins
  module QEMU
    class Config < Vagrant.plugin("2", :config)
      attr_accessor :ssh_host
      attr_accessor :ssh_port
      attr_accessor :ssh_auto_correct
      attr_accessor :arch
      attr_accessor :machine
      attr_accessor :cpu
      attr_accessor :smp
      attr_accessor :memory
      attr_accessor :net_device
      attr_accessor :drive_interface
      attr_accessor :image_path
      attr_accessor :qemu_bin
      attr_accessor :qemu_dir
      attr_accessor :disk_resize
      attr_accessor :extra_qemu_args
      attr_accessor :extra_netdev_args
      attr_accessor :extra_drive_args
      attr_accessor :control_port
      attr_accessor :debug_port
      attr_accessor :no_daemonize
      attr_accessor :firmware_format
      attr_accessor :other_default
      attr_accessor :extra_image_opts
      attr_accessor :graceful_timeout  # seconds to wait for guest shutdown before force kill
      # Advanced networking options
      attr_accessor :advanced_network   # bool, opt-in for dual-NIC setup
      attr_accessor :net_mode           # :auto, :vmnet_shared, :vmnet_host, :vmnet_bridged, :tap, :socket
      attr_accessor :vmnet_interface    # physical interface for vmnet-bridged (e.g. "en0")
      attr_accessor :tap_device         # tap device name for Linux tap backend
      attr_accessor :mcast_addr         # convenience shortcut for the :socket backend's multicast address
      # Raw QEMU `socket` netdev options for the :socket backend; whatever you
      # set is emitted verbatim as `-netdev socket,id=netN,<socket_opts>`, e.g.
      # "mcast=230.0.0.1:1234", "listen=:1234", "connect=127.0.0.1:1234".
      # The mode (multicast vs point-to-point listen/connect) and any roles are
      # entirely the user's choice. Overrides mcast_addr when set.
      attr_accessor :socket_opts

      def initialize
        @ssh_host = UNSET_VALUE
        @ssh_port = UNSET_VALUE
        @ssh_auto_correct = UNSET_VALUE
        @arch = UNSET_VALUE
        @machine = UNSET_VALUE
        @cpu = UNSET_VALUE
        @smp = UNSET_VALUE
        @memory = UNSET_VALUE
        @net_device = UNSET_VALUE
        @drive_interface = UNSET_VALUE
        @image_path = UNSET_VALUE
        @qemu_bin = UNSET_VALUE
        @qemu_dir = UNSET_VALUE
        @disk_resize = UNSET_VALUE
        @extra_qemu_args = UNSET_VALUE
        @extra_netdev_args = UNSET_VALUE
        @extra_drive_args = UNSET_VALUE
        @control_port = UNSET_VALUE
        @debug_port = UNSET_VALUE
        @no_daemonize = UNSET_VALUE
        @firmware_format = UNSET_VALUE
        @other_default = UNSET_VALUE
        @extra_image_opts = UNSET_VALUE
        @graceful_timeout = UNSET_VALUE
        @advanced_network = UNSET_VALUE
        @net_mode = UNSET_VALUE
        @vmnet_interface = UNSET_VALUE
        @tap_device = UNSET_VALUE
        @mcast_addr = UNSET_VALUE
        @socket_opts = UNSET_VALUE
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
        @ssh_auto_correct = false if @ssh_auto_correct == UNSET_VALUE
        # Resolve arch first; the binary is qemu-system-<arch> and every other
        # default below keys off the *resolved* arch (so setting only qe.arch
        # still yields a consistent machine/cpu/net_device/qemu_dir).
        @arch = host_arch if @arch == UNSET_VALUE

        # Native virtualization (guest arch == host arch) uses the host's
        # hardware accelerator with cpu=host; cross-arch emulation falls back to
        # TCG with cpu=max (host is invalid under TCG).
        native = (@arch == host_arch)
        base_machine = (@arch == "aarch64" ? "virt,highmem=on" : "q35")
        accel = native ? host_accel : "tcg"
        @machine = "#{base_machine},accel=#{accel}" if @machine == UNSET_VALUE
        @cpu = (native ? "host" : "max") if @cpu == UNSET_VALUE
        @smp = "2" if @smp == UNSET_VALUE
        @memory = "4G" if @memory == UNSET_VALUE
        @net_device = (@arch == "aarch64" ? "virtio-net-device" : "virtio-net-pci") if @net_device == UNSET_VALUE
        @drive_interface = "virtio" if @drive_interface == UNSET_VALUE
        @image_path = nil if @image_path == UNSET_VALUE
        @qemu_bin = nil if @qemu_bin == UNSET_VALUE
        @qemu_dir = default_qemu_dir(@arch) if @qemu_dir == UNSET_VALUE
        @disk_resize = nil if @disk_resize == UNSET_VALUE
        @extra_qemu_args = [] if @extra_qemu_args == UNSET_VALUE
        @extra_netdev_args = nil if @extra_netdev_args == UNSET_VALUE
        @extra_drive_args = nil if @extra_drive_args == UNSET_VALUE
        @control_port = nil if @control_port == UNSET_VALUE
        @debug_port = nil if @debug_port == UNSET_VALUE
        @no_daemonize = false if @no_daemonize == UNSET_VALUE
        @firmware_format = "raw" if @firmware_format == UNSET_VALUE
        @other_default = %W(-parallel null -monitor none -display none -vga none) if @other_default == UNSET_VALUE
        @extra_image_opts = nil if @extra_image_opts == UNSET_VALUE
        @graceful_timeout = 60 if @graceful_timeout == UNSET_VALUE
        @advanced_network = false if @advanced_network == UNSET_VALUE
        @net_mode = :auto if @net_mode == UNSET_VALUE
        @vmnet_interface = "en0" if @vmnet_interface == UNSET_VALUE
        @tap_device = nil if @tap_device == UNSET_VALUE
        @mcast_addr = nil if @mcast_addr == UNSET_VALUE
        @socket_opts = nil if @socket_opts == UNSET_VALUE

        # TODO better error msg
        @ssh_port = Integer(@ssh_port)
        @graceful_timeout = Integer(@graceful_timeout)
      end

      def validate(machine)
        # errors = _detected_errors
        errors = []
        { "QEMU Provider" => errors }
      end

      private

      # Normalized architecture of the host running QEMU. Apple Silicon Ruby
      # reports "arm64"; everything arm-like maps to "aarch64", else "x86_64".
      def host_arch
        RbConfig::CONFIG["host_cpu"] =~ /arm|aarch64/ ? "aarch64" : "x86_64"
      end

      # Hardware accelerator for the host OS (used only for native virt).
      def host_accel
        case RbConfig::CONFIG["host_os"]
        when /darwin/ then "hvf"
        when /mswin|mingw|cygwin/ then "whpx"
        else "kvm"
        end
      end

      # QEMU data dir (firmware images). Only actually consumed for aarch64
      # firmware, but resolved generically: explicit env override, then the
      # Homebrew prefix, then a per-platform default.
      def default_qemu_dir(arch)
        return ENV["QEMU_DIR"] if ENV["QEMU_DIR"]
        return "#{ENV['HOMEBREW_PREFIX']}/share/qemu" if ENV["HOMEBREW_PREFIX"]

        case RbConfig::CONFIG["host_os"]
        when /darwin/
          arch == "aarch64" ? "/opt/homebrew/share/qemu" : "/usr/local/share/qemu"
        else
          "/usr/share/qemu"
        end
      end
    end
  end
end
