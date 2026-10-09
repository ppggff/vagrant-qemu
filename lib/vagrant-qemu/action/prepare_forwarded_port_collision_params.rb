require "socket"

module VagrantPlugins
  module QEMU
    module Action
    class PrepareForwardedPortCollisionParams
      def initialize(app, env)
      @app = app
      end

      def call(env)
      machine = env[:machine]

      # TODO: not supported
      other_used_ports = {}
      env[:port_collision_extra_in_use] = other_used_ports

      # Build the remap for any existing collision detections
      remap = {}
      env[:port_collision_remap] = remap

      # Windows keeps Vagrant's per-interface check for 0.0.0.0.
      if !Vagrant::Util::Platform.windows?
        env[:port_collision_port_check] = lambda do |host_ip, host_port|
          self.class.port_in_use?(host_ip || "0.0.0.0", host_port)
        end
      end

      has_ssh_forward = false
      machine.config.vm.networks.each do |type, options|
        next if type != :forwarded_port

        # update ssh.host to ssh_port
        if options[:id] == "ssh"
          options[:host] = machine.provider_config.ssh_port
          options[:auto_correct] = machine.provider_config.ssh_auto_correct
          has_ssh_forward = true
          break
        end
      end

      if !has_ssh_forward
        machine.config.vm.network :forwarded_port,
          :guest => 22, 
          :host => machine.provider_config.ssh_port, 
          :host_ip => "127.0.0.1", 
          :id => "ssh", 
          :auto_correct => machine.provider_config.ssh_auto_correct,
          :protocol => "tcp"
      end

      @app.call(env)
      end

      # Vagrant's IsPortOpen with an extra getpeername: on macOS 27 a refused
      # non-blocking connect reports EISCONN on the retry, so Socket.tcp
      # returns an unconnected socket and every port looks in use.
      def self.port_in_use?(host, port)
        Socket.tcp(host, port, connect_timeout: 0.1) do |sock|
          sock.remote_address
          true
        end
      rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
          Errno::ENETUNREACH, Errno::EACCES, Errno::ENOTCONN, Errno::EALREADY,
          Errno::EINVAL
        false
      end
    end
    end
  end
end
