require "spec_helper"

describe VagrantPlugins::QEMU::Network, ".build_network_config" do
  let(:mac0) { "52:54:00:aa:bb:01" }
  let(:mac1) { "52:54:00:aa:bb:02" }

  subject do
    described_class.build_network_config(
      mac0: mac0, mac1: mac1,
      ip: "192.168.105.10", netmask: "255.255.255.0"
    )
  end

  it "produces valid YAML" do
    expect { YAML.safe_load(subject) }.not_to raise_error
  end

  it "sets user-nic to match mac0 with dhcp4" do
    parsed = YAML.safe_load(subject)
    user_nic = parsed["network"]["ethernets"]["user-nic"]
    expect(user_nic["match"]["macaddress"]).to eq mac0
    expect(user_nic["dhcp4"]).to eq true
  end

  it "sets private-nic to match mac1 with correct IP/prefix" do
    parsed = YAML.safe_load(subject)
    priv_nic = parsed["network"]["ethernets"]["private-nic"]
    expect(priv_nic["match"]["macaddress"]).to eq mac1
    expect(priv_nic["addresses"]).to eq ["192.168.105.10/24"]
  end

  it "calculates /16 prefix for 255.255.0.0 netmask" do
    result = described_class.build_network_config(
      mac0: mac0, mac1: mac1,
      ip: "10.0.1.5", netmask: "255.255.0.0"
    )
    parsed = YAML.safe_load(result)
    expect(parsed["network"]["ethernets"]["private-nic"]["addresses"]).to eq ["10.0.1.5/16"]
  end
end
