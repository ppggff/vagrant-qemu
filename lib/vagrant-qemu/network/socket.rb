require_relative "base"

module VagrantPlugins
  module QEMU
    module Network
      # QEMU `socket` netdev backend -- a thin wrapper, not an abstraction.
      #
      # Whatever the user puts in `socket_opts` is emitted verbatim as the
      # netdev options, so the mode is entirely the user's choice:
      #   socket_opts: "mcast=230.0.0.1:1234"   -> multicast, N-way (Linux/Windows)
      #   socket_opts: "listen=:1234"           -> point-to-point, this VM listens
      #   socket_opts: "connect=127.0.0.1:1234" -> point-to-point, this VM connects
      # For listen/connect the user decides which VM listens and which connects;
      # the plugin does not assign roles. (listen/connect is the no-root,
      # macOS-friendly path; mcast does not work on macOS.)
      #
      # When `socket_opts` is unset it falls back to multicast using `mcast_addr`
      # (default 230.0.0.1:1234) for backward compatibility.
      class Socket < Base
        def build_netdev_args(id, options)
          opts = options[:socket_opts]
          opts = "mcast=#{options[:mcast_addr] || "230.0.0.1:1234"}" if opts.nil? || opts.empty?
          %W(-netdev socket,id=#{id},#{opts})
        end
      end
    end
  end
end
