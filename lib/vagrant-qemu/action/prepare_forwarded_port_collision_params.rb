
require 'open3'

module VagrantPlugins
  module QEMU
    module Action
    class PrepareForwardedPortCollisionParams
      def initialize(app, env)
      @app = app
      @logger = Log4r::Logger.new("vagrant_qemu::action::prepare_forwarded_port_collision_params")
      end

      def call(env)
      machine = env[:machine]

      other_used_ports = Hash.new{|hash, key| hash[key] = Set.new}

      ps_output, _status = Open3.capture2("ps -eo pid,comm,user,command")
      ps_output.each_line do |line|
        next if line =~ /^\s*PID/

        columns = line.split
        pid, comm, user = columns[0], columns[1], columns[2]
        cmdline = columns[3..-1].join(" ")

        if comm.include?('qemu-system') && cmdline =~ /hostfwd=tcp::(\d+)-:22/
          port = $1
          other_used_ports[port].add?('*')
        end
      end

      #puts other_used_ports
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
        machine.config.vm.networks.forward_port(22, machine.provider_config.ssh_port, [id: "ssh", auto_correct: true])
      end

      @app.call(env)
      end
    end
    end
  end
end
