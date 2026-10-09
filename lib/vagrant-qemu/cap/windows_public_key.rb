require Vagrant.source_root.join("plugins/guests/windows/cap/public_key").to_s

module VagrantPlugins
  module QEMU
    module Cap
      module WindowsPublicKey
        def self.remove_public_key(machine, contents)
          unless machine.communicate.is_a?(CommunicatorWinSSH::Communicator)
            raise Vagrant::Errors::SSHInsertKeyUnsupported
          end
          GuestWindows::Cap::PublicKey.winssh_modify_authorized_keys(machine) do |keys|
            contents.each_line do |line|
              key = line.strip
              keys.delete(key) unless key.empty?
            end
          end
        end
      end
    end
  end
end
