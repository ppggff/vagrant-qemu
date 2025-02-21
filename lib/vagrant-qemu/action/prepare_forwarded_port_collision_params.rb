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
    end
    end
  end
end
