module VagrantPlugins
  module QEMU
    module Network
      class Base
        # Build -netdev arguments for the advanced network NIC
        # @param id [String] netdev id (e.g. "net1")
        # @param options [Hash] provider config options
        # @return [Array<String>] QEMU command line arguments
        def build_netdev_args(id, options)
          raise NotImplementedError
        end

        # Whether this backend requires sudo to run QEMU
        # @return [Boolean]
        def requires_sudo?
          false
        end

        # Tokens to prepend to the QEMU launch command (a wrapper program).
        # Empty by default; only socket_vmnet's wrapper route is non-empty.
        # The driver applies this under the same gate as build_netdev_args.
        # @param options [Hash] provider config options
        # @return [Array<String>]
        def launch_prefix(options)
          []
        end

        # Validate preconditions and resolve any backend-specific options
        # before the command is built. No-op by default; the driver calls it
        # under the same gate as build_netdev_args.
        # @param options [Hash] provider config options (may be mutated)
        # @param qemu_binary [String] the resolved qemu-system-* binary
        def preflight!(options, qemu_binary)
        end
      end
    end
  end
end
