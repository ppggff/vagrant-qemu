require "json"

module VagrantPlugins
  module QEMU
    module Cap
      module ForwardedPorts
        # Vagrant port expects integer host=>guest mappings, not configured ports.
        def self.forwarded_ports(machine)
          return nil unless machine.state.id == :running
          path = machine.provider.driver.tmp_dir.join(machine.id, "runtime.json")
          argv = JSON.parse(File.read(path)).fetch("argv")
          result = {}
          argv.each_cons(2) do |flag, value|
            next unless flag == "-netdev"
            value.split(",").each do |option|
              match = /\Ahostfwd=tcp:.*:(\d+)-.*:(\d+)\z/.match(option)
              result[Integer(match[1])] = Integer(match[2]) if match
            end
          end
          result
        end
      end
    end
  end
end
