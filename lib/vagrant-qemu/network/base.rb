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
      end
    end
  end
end
