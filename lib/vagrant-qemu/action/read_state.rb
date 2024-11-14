require "log4r"
require 'sys/proctable'
include Sys

module VagrantPlugins
  module QEMU
    module Action
      # This action reads the state of the machine and puts it in the
      # `:machine_state_id` key in the environment.
      class ReadState
        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_qemu::action::read_state")
        end

        def call(env)
          if env[:machine].id
            env[:machine_state_id] = env[:machine].provider.driver.get_current_state

            # If the machine isn't created, then our ID is stale, so just
            # mark it as not created.
            if env[:machine_state_id] == :not_created
              env[:machine].id = nil
            end
          else
            env[:machine_state_id] = :not_created
          end
          if env[:machine].provider_config.ssh_port != nil
            options = {
              :control_port => env[:machine].provider_config.control_port,
              :ssh_port => env[:machine].provider_config.ssh_port
            }
            env[:machine].provider_config.ssh_port=env[:machine].provider.driver.get_ssh_port(options)
          end
          @app.call(env)
        end
      end
    end
  end
end
