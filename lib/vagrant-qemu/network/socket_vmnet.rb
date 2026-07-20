require_relative "base"

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
      # so they never disagree (see design ADR-0001).
      class SocketVmnet < Base
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

        def requires_sudo?
          false
        end
      end
    end
  end
end
