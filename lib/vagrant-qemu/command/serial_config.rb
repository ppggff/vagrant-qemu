require "optparse"
require "json"

module VagrantPlugins
  module QEMU
    module Command
      class SerialConfig < Vagrant.plugin("2", :command)
        def self.synopsis
          "shows each QEMU machine's serial endpoint"
        end

        def execute
          json = false
          parser = OptionParser.new do |options|
            options.banner = "Usage: vagrant serial-config [options] [name|id]"
            options.on("--json", "Output machine names and endpoints as JSON") { json = true }
          end
          argv = parse_options(parser)
          return if argv.nil?

          records = []
          with_target_vms(argv, provider: :qemu) do |machine|
            unless machine.provider_name == :qemu
              raise Vagrant::Errors::ActiveMachineWithDifferentProvider,
                name: machine.name.to_s, active_provider: machine.provider_name.to_s,
                requested_provider: "qemu"
            end

            endpoint = if machine.id
              machine.provider.driver.serial_endpoint(machine.provider_config.debug_port)
            end
            records << { machine: machine.name.to_s, endpoint: endpoint }
          end

          if json
            @env.ui.output(JSON.generate(records))
          else
            records.each do |record|
              endpoint = record[:endpoint]
              lines = ["Machine #{record[:machine]}"]
              if endpoint.nil?
                lines << "  NotCreated"
              elsif endpoint[:type] == :unix
                lines << "  UnixSocket #{endpoint[:path]}"
              else
                lines << "  Host #{endpoint[:host]}" << "  Port #{endpoint[:port]}"
              end
              @env.ui.output(lines.join("\n"))
            end
          end
          0
        end
      end
    end
  end
end
