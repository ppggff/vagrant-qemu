require "spec_helper"

describe VagrantPlugins::QEMU::Network::Vmnet do
  subject { described_class.new }

  it "builds vmnet-shared args without subnet when no private_networks" do
    args = subject.build_netdev_args("net1", net_mode: :vmnet_shared)
    expect(args).to eq %w(-netdev vmnet-shared,id=net1)
  end

  it "builds vmnet-shared args with subnet derived from IP" do
    args = subject.build_netdev_args("net1",
      net_mode: :vmnet_shared,
      private_networks: [{ ip: "192.168.105.10", netmask: "255.255.255.0" }]
    )
    netdev_arg = args.last
    expect(netdev_arg).to include("vmnet-shared,id=net1")
    expect(netdev_arg).to include("start-address=192.168.105.1")
    expect(netdev_arg).to include("end-address=192.168.105.254")
    expect(netdev_arg).to include("subnet-mask=255.255.255.0")
  end

  it "builds vmnet-host args with subnet" do
    args = subject.build_netdev_args("net1",
      net_mode: :vmnet_host,
      private_networks: [{ ip: "10.0.1.5", netmask: "255.255.0.0" }]
    )
    netdev_arg = args.last
    expect(netdev_arg).to include("vmnet-host,id=net1")
    expect(netdev_arg).to include("start-address=10.0.0.1")
    expect(netdev_arg).to include("end-address=10.0.255.254")
    expect(netdev_arg).to include("subnet-mask=255.255.0.0")
  end

  it "builds vmnet-bridged args without subnet (physical network decides)" do
    args = subject.build_netdev_args("net1",
      net_mode: :vmnet_bridged,
      vmnet_interface: "en0",
      private_networks: [{ ip: "192.168.1.100" }]
    )
    expect(args).to eq %w(-netdev vmnet-bridged,id=net1,ifname=en0)
  end

  it "defaults netmask to 255.255.255.0" do
    args = subject.build_netdev_args("net1",
      net_mode: :vmnet_shared,
      private_networks: [{ ip: "172.16.0.10" }]
    )
    netdev_arg = args.last
    expect(netdev_arg).to include("subnet-mask=255.255.255.0")
    expect(netdev_arg).to include("start-address=172.16.0.1")
    expect(netdev_arg).to include("end-address=172.16.0.254")
  end

  it "requires sudo" do
    expect(subject.requires_sudo?).to eq true
  end
end
