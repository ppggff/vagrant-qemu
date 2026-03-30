require "spec_helper"

describe VagrantPlugins::QEMU::Network::Vmnet do
  subject { described_class.new }

  it "builds vmnet-shared args" do
    args = subject.build_netdev_args("net1", net_mode: :vmnet_shared)
    expect(args).to eq %w(-netdev vmnet-shared,id=net1)
  end

  it "builds vmnet-host args" do
    args = subject.build_netdev_args("net1", net_mode: :vmnet_host)
    expect(args).to eq %w(-netdev vmnet-host,id=net1)
  end

  it "builds vmnet-bridged args with ifname" do
    args = subject.build_netdev_args("net1", net_mode: :vmnet_bridged, vmnet_interface: "en0")
    expect(args).to eq %w(-netdev vmnet-bridged,id=net1,ifname=en0)
  end

  it "requires sudo" do
    expect(subject.requires_sudo?).to eq true
  end
end
