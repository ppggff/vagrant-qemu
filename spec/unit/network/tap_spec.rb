require "spec_helper"

describe VagrantPlugins::QEMU::Network::Tap do
  subject { described_class.new }

  it "builds tap args with default tap0" do
    args = subject.build_netdev_args("net1", {})
    expect(args).to eq %w(-netdev tap,id=net1,ifname=tap0,script=no,downscript=no)
  end

  it "builds tap args with custom device" do
    args = subject.build_netdev_args("net1", tap_device: "tap1")
    expect(args).to eq %w(-netdev tap,id=net1,ifname=tap1,script=no,downscript=no)
  end
end
