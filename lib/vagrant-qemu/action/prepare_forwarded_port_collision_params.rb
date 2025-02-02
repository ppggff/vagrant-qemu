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

      has_ssh_forward = false
      machine.config.vm.networks.each do |type, options|
        next if type != :forwarded_port

        # remap ssh.host to ssh_port
        if options[:id] == "ssh"
          remap[options[:host]] = machine.provider_config.ssh_port
          has_ssh_forward = true
          break
        end
      end

      if !has_ssh_forward
        machine.config.vm.networks.forward_port(22, machine.provider_config.ssh_port, [id: "ssh", auto_correct: machine.provider_config.ssh_auto_correct])
      end

      @app.call(env)
      end
    end
    end
  end
end
