require "ipaddr"
require_relative "base"

module VagrantPlugins
  module QEMU
    module Network
      # macOS vmnet.framework backend (QEMU >= 7.0)
      # Supports vmnet-shared, vmnet-host, vmnet-bridged
      class Vmnet < Base
        def build_netdev_args(id, options)
          case options[:net_mode]
          when :vmnet_shared
            base = "vmnet-shared,id=#{id}"
            base += subnet_args(options)
            %W(-netdev #{base})
          when :vmnet_host
            base = "vmnet-host,id=#{id}"
            base += subnet_args(options)
            %W(-netdev #{base})
          when :vmnet_bridged
            ifname = options[:vmnet_interface] || "en0"
            %W(-netdev vmnet-bridged,id=#{id},ifname=#{ifname})
          end
        end

        def requires_sudo?
          true
        end

        private

        # Derive vmnet subnet parameters from the user's private_network IP.
        # vmnet requires start-address, end-address, subnet-mask all together.
        #
        # @param options [Hash]
        # @return [String] comma-prefixed parameter string, or empty
        def subnet_args(options)
          pn = (options[:private_networks] || []).first
          return "" unless pn && pn[:ip]

          netmask = pn[:netmask] || "255.255.255.0"
          network = IPAddr.new("#{pn[:ip]}/#{netmask}")

          # start-address = network + 1 (gateway), end-address = broadcast - 1
          start_addr = IPAddr.new(network.to_i + 1, ::Socket::AF_INET)
          end_addr = IPAddr.new(network.to_i | (~IPAddr.new(netmask).to_i & 0xFFFFFFFF) - 1, ::Socket::AF_INET)

          ",start-address=#{start_addr},end-address=#{end_addr},subnet-mask=#{netmask}"
        end
      end
    end
  end
end
