require_relative "base"

module VagrantPlugins
  module QEMU
    module Network
      # QEMU socket multicast backend (cross-platform fallback)
      # Provides VM-to-VM communication without external dependencies
      # Note: host cannot directly access VM IPs in this mode
      class Socket < Base
        def build_netdev_args(id, options)
          mcast_addr = options[:mcast_addr] || "230.0.0.1:1234"
          %W(-netdev socket,id=#{id},mcast=#{mcast_addr})
        end
      end
    end
  end
end
