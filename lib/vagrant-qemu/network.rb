require_relative "network/base"
require_relative "network/vmnet"
require_relative "network/tap"
require_relative "network/socket"
require_relative "network/socket_vmnet"

module VagrantPlugins
  module QEMU
    module Network
      # Select the appropriate network backend based on net_mode and platform.
      #
      # @param net_mode [Symbol] :auto, :vmnet_shared, :vmnet_host,
      #   :vmnet_bridged, :tap, :socket, :socket_vmnet
      # @return [Base] a network backend instance
      def self.backend_for(net_mode)
        case net_mode
        when :vmnet_shared, :vmnet_host, :vmnet_bridged
          Vmnet.new
        when :tap
          Tap.new
        when :socket
          Socket.new
        when :socket_vmnet
          SocketVmnet.new
        when :auto
          auto_detect
        else
          raise Errors::ConfigError, err: "Unknown net_mode: #{net_mode}"
        end
      end

      # Auto-detect the best backend for the current platform.
      # @return [Base]
      def self.auto_detect
        case RbConfig::CONFIG['host_os']
        when /darwin/
          Vmnet.new
        when /linux/
          Tap.new
        else
          Socket.new
        end
      end

      # Whether the QEMU binary has the native `stream` netdev (QEMU >= 7.2),
      # so socket_vmnet can connect to the daemon's unix socket directly
      # instead of going through the socket_vmnet_client wrapper.
      #
      # Probes `<qemu> -M none -netdev help` and looks for a `stream` line on
      # stdout. Cached per binary.
      #
      # Tri-state so the driver can honor the design's fallback direction:
      #   true  -- probe ran, stream present  -> use stream
      #   false -- probe ran, stream absent    -> use the wrapper (old QEMU)
      #   nil   -- probe could not run (rare)  -> driver defaults to stream
      #
      # @param qemu_binary [String] path/name of the qemu-system-* binary
      # @return [Boolean, nil]
      def self.qemu_supports_stream?(qemu_binary)
        @stream_support ||= {}
        return @stream_support[qemu_binary] if @stream_support.key?(qemu_binary)

        result =
          begin
            out = ::Vagrant::Util::Subprocess.execute(qemu_binary, "-M", "none", "-netdev", "help")
            out.exit_code == 0 ? out.stdout.lines.any? { |l| l.strip == "stream" } : nil
          rescue StandardError
            nil
          end
        @stream_support[qemu_binary] = result
      end

      # Generate a deterministic MAC address from vm_id and NIC index.
      # Uses 52:54:00 prefix (QEMU's OUI).
      #
      # @param vm_id [String]
      # @param nic_index [Integer]
      # @return [String] MAC address like "52:54:00:ab:cd:ef"
      def self.generate_mac(vm_id, nic_index)
        require 'digest'
        hash = Digest::MD5.hexdigest("#{vm_id}-#{nic_index}")
        "52:54:00:#{hash[0..1]}:#{hash[2..3]}:#{hash[4..5]}"
      end

      # MAC pair for the dual-NIC setup; NIC 1 honors a user-specified MAC.
      # Single source of truth so the QEMU command line (driver) and the
      # cloud-init network-config (CloudInitNetwork action) never diverge.
      #
      # @param vm_id [String]
      # @param pn [Hash, nil] first private_network options
      # @return [Array(String, String)] [mac0, mac1]
      def self.nic_macs(vm_id, pn)
        [generate_mac(vm_id, 0), (pn && pn[:mac]) || generate_mac(vm_id, 1)]
      end

      # Build cloud-init network-config v2 YAML for dual-NIC setup.
      # Only called when advanced_network is enabled and private_network is configured.
      #
      # @param mac0 [String] MAC of user-mode NIC (DHCP)
      # @param mac1 [String] MAC of advanced network NIC
      # @param ip [String] static IP for the advanced NIC (e.g. "192.168.105.10")
      # @param netmask [String] netmask (e.g. "255.255.255.0")
      # @return [String] YAML string
      def self.build_network_config(mac0:, mac1:, ip:, netmask: "255.255.255.0")
        require 'ipaddr'
        require 'yaml'

        prefix = IPAddr.new(netmask).to_i.to_s(2).count("1")

        config = {
          "network" => {
            "version" => 2,
            "ethernets" => {
              "user-nic" => {
                "match" => { "macaddress" => mac0 },
                "dhcp4" => true
              },
              "private-nic" => {
                "match" => { "macaddress" => mac1 },
                "addresses" => ["#{ip}/#{prefix}"]
              }
            }
          }
        }

        config.to_yaml
      end
    end
  end
end
