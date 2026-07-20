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

      class ConfigError < VagrantQEMUError
        error_key(:config_error)
      end

      class QemuBinaryNotFound < VagrantQEMUError
        error_key(:qemu_binary_not_found)
      end

      class DestroyError < VagrantQEMUError
        error_key(:destroy_error)
      end

      class SocketVmnetNotMacos < VagrantQEMUError
        error_key(:socket_vmnet_not_macos)
      end

      class SocketVmnetSocketNotFound < VagrantQEMUError
        error_key(:socket_vmnet_socket_not_found)
      end

      class SocketVmnetClientNotFound < VagrantQEMUError
        error_key(:socket_vmnet_client_not_found)
      end
    end
  end
end
