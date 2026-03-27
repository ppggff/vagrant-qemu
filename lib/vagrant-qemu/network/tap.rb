require_relative "base"

module VagrantPlugins
  module QEMU
    module Network
      # Linux TAP backend
      # Requires pre-created tap device and bridge
      class Tap < Base
        def build_netdev_args(id, options)
          tap_device = options[:tap_device] || "tap0"
          %W(-netdev tap,id=#{id},ifname=#{tap_device},script=no,downscript=no)
        end

        def requires_sudo?
          true
        end
      end
    end
  end
end
