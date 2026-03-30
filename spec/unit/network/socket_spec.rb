require "spec_helper"

describe VagrantPlugins::QEMU::Network::Socket do
  subject { described_class.new }

  it "builds socket args with default mcast address" do
    args = subject.build_netdev_args("net1", {})
    expect(args).to eq %w(-netdev socket,id=net1,mcast=230.0.0.1:1234)
  end

  it "builds socket args with custom mcast address" do
    args = subject.build_netdev_args("net1", mcast_addr: "230.0.0.2:5678")
    expect(args).to eq %w(-netdev socket,id=net1,mcast=230.0.0.2:5678)
  end
end
