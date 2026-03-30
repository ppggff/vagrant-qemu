require "spec_helper"

describe VagrantPlugins::QEMU::Network, ".generate_mac" do
  it "returns MAC in 52:54:00:xx:xx:xx format" do
    mac = described_class.generate_mac("vq_test", 0)
    expect(mac).to match(/\A52:54:00:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}\z/)
  end

  it "is deterministic for same inputs" do
    mac1 = described_class.generate_mac("vq_test", 0)
    mac2 = described_class.generate_mac("vq_test", 0)
    expect(mac1).to eq mac2
  end

  it "produces different MACs for different NIC indices" do
    mac0 = described_class.generate_mac("vq_test", 0)
    mac1 = described_class.generate_mac("vq_test", 1)
    expect(mac0).not_to eq mac1
  end

  it "produces different MACs for different VM IDs" do
    mac_a = described_class.generate_mac("vq_aaa", 0)
    mac_b = described_class.generate_mac("vq_bbb", 0)
    expect(mac_a).not_to eq mac_b
  end
end
