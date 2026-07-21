require_relative "base"
require_relative "../errors"

module VagrantPlugins
  module QEMU
    module Network
      # socket_vmnet backend (macOS) -- connects the private NIC to a
      # socket_vmnet daemon so QEMU runs without sudo (the daemon holds the
      # root vmnet.framework membership).
      #
      # Two routes, chosen by whether the QEMU binary has the native `stream`
      # netdev (options[:use_stream], set by the driver from a probe):
      #   stream (QEMU >= 7.2): QEMU connects to the daemon's unix socket
      #     directly -- a pure netdev backend, no launch wrapper.
      #   wrapper (older QEMU): QEMU is launched under `socket_vmnet_client
      #     <sock>`, which hands the connection in on fd 3.
      #
      # build_netdev_args and launch_prefix are driven by the same use_stream
      # so they never disagree.
      class SocketVmnet < Base
        # Resolve the route and fail fast on missing preconditions. Sets
        # options[:use_stream]: true when the qemu binary has the native
        # `stream` netdev, false when it definitively lacks it, and true when
        # the probe couldn't determine (rare) -- stream needs no extra dependency.
        def preflight!(options, qemu_binary)
          raise Errors::SocketVmnetNotMacos unless RbConfig::CONFIG["host_os"] =~ /darwin/

          options[:use_stream] = Network.qemu_supports_stream?(qemu_binary) != false

          socket = options[:socket_vmnet_socket]
          unless socket && File.exist?(socket)
            raise Errors::SocketVmnetSocketNotFound, socket: socket
          end

          return if options[:use_stream]

          client = options[:socket_vmnet_client]
          unless client && (::Vagrant::Util::Which.which(client) || File.executable?(client))
            raise Errors::SocketVmnetClientNotFound, client: client
          end
        end

        def build_netdev_args(id, options)
          if options[:use_stream]
            sock = options[:socket_vmnet_socket]
            %W(-netdev stream,id=#{id},server=off,addr.type=unix,addr.path=#{sock})
          else
            %W(-netdev socket,id=#{id},fd=3)
          end
        end

        def launch_prefix(options)
          return [] if options[:use_stream]

          %W(#{options[:socket_vmnet_client]} #{options[:socket_vmnet_socket]})
        end
      end
    end
  end
end
