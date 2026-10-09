require "spec_helper"
require "vagrant-qemu/cap/windows_public_key"

describe VagrantPlugins::QEMU::Cap::WindowsPublicKey do
  let(:comm) { instance_double(VagrantPlugins::CommunicatorWinSSH::Communicator) }
  let(:machine) { double("machine", communicate: comm) }
  let(:helper) { VagrantPlugins::GuestWindows::Cap::PublicKey }

  before { allow(comm).to receive(:is_a?).with(VagrantPlugins::CommunicatorWinSSH::Communicator).and_return(true) }

  it "registers the standard Windows remove_public_key guest capability" do
    capability = VagrantPlugins::QEMU::Plugin.components.guest_capabilities[:windows].get(:remove_public_key)
    expect(capability).to eq(described_class)
  end

  it "removes every nonempty supplied line and duplicates but keeps unrelated keys through the existing helper" do
    bootstrap = Vagrant.source_root.join("keys", "vagrant.pub").read
    supplied = bootstrap.lines.map(&:strip).reject(&:empty?)
    keys = supplied + supplied + ["unrelated"]
    expect(helper).to receive(:winssh_modify_authorized_keys).with(machine).and_yield(keys)
    described_class.remove_public_key(machine, "\r\n  " + supplied.join(" \r\n  ") + " \r\n\n")
    expect(keys).to eq(["unrelated"])
  end

  it "preserves the existing unsupported-communicator error before modifying files" do
    allow(comm).to receive(:is_a?).with(VagrantPlugins::CommunicatorWinSSH::Communicator).and_return(false)
    expect(helper).not_to receive(:winssh_modify_authorized_keys)
    expect { described_class.remove_public_key(machine, "key") }.to raise_error(Vagrant::Errors::SSHInsertKeyUnsupported)
  end
end
