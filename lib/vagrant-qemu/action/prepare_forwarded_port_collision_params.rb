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
  
			@app.call(env)
		  end
		end
	  end
	end
  end
  