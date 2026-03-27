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
            %W(-netdev vmnet-shared,id=#{id})
          when :vmnet_host
            %W(-netdev vmnet-host,id=#{id})
          when :vmnet_bridged
            ifname = options[:vmnet_interface] || "en0"
            %W(-netdev vmnet-bridged,id=#{id},ifname=#{ifname})
          end
        end

        def requires_sudo?
          true
        end
      end
    end
  end
end
