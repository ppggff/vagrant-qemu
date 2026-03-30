require "spec_helper"

describe VagrantPlugins::QEMU::Network, ".backend_for" do
  it "returns Vmnet for :vmnet_shared" do
    expect(described_class.backend_for(:vmnet_shared)).to be_a(VagrantPlugins::QEMU::Network::Vmnet)
  end

  it "returns Vmnet for :vmnet_host" do
    expect(described_class.backend_for(:vmnet_host)).to be_a(VagrantPlugins::QEMU::Network::Vmnet)
  end

  it "returns Vmnet for :vmnet_bridged" do
    expect(described_class.backend_for(:vmnet_bridged)).to be_a(VagrantPlugins::QEMU::Network::Vmnet)
  end

  it "returns Tap for :tap" do
    expect(described_class.backend_for(:tap)).to be_a(VagrantPlugins::QEMU::Network::Tap)
  end

  it "returns Socket for :socket" do
    expect(described_class.backend_for(:socket)).to be_a(VagrantPlugins::QEMU::Network::Socket)
  end

  it "raises ConfigError for unknown net_mode" do
    expect { described_class.backend_for(:bogus) }.to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
  end
end
