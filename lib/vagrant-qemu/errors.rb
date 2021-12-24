require "vagrant"

module VagrantPlugins
  module QEMU
    module Errors
      class VagrantQEMUError < Vagrant::Errors::VagrantError
        error_namespace("vagrant_qemu.errors")
      end

      class RsyncError < VagrantQEMUError
        error_key(:rsync_error)
      end

      class MkdirError < VagrantQEMUError
        error_key(:mkdir_error)
      end

      class NotSupportedError < VagrantQEMUError
        error_key(:not_supported)
      end

      class BoxInvalid < VagrantQEMUError
        error_key(:box_invalid)
      end

      class ExecuteError < VagrantQEMUError
        error_key(:execute_error)
      end
    end
  end
end
