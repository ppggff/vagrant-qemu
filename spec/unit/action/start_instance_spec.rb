require "spec_helper"

describe VagrantPlugins::QEMU::Action::StartInstance do
  let(:app) { double("app", call: nil) }

  it "passes all config options to driver.start" do
    ctx = mock_vagrant_env(
      provider_config_overrides: { memory: "8G", advanced_network: true, net_mode: :vmnet_shared },
      networks: [[:forwarded_port, { id: "ssh", host: 50022, guest: 22, protocol: "tcp" }]]
    )
    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(received_options[:memory]).to eq "8G"
    expect(received_options[:advanced_network]).to eq true
    expect(received_options[:net_mode]).to eq :vmnet_shared
  end

  it "collects private_networks from vm.networks" do
    ctx = mock_vagrant_env(
      networks: [
        [:forwarded_port, { id: "ssh", host: 50022, guest: 22, protocol: "tcp" }],
        [:private_network, { ip: "192.168.105.10", netmask: "255.255.255.0" }],
      ]
    )
    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(received_options[:private_networks]).to eq [{ ip: "192.168.105.10", netmask: "255.255.255.0" }]
  end

  describe "#forwarded_ports" do
    it "skips SSH port" do
      ctx = mock_vagrant_env(networks: [
        [:forwarded_port, { id: "ssh", host: 50022, guest: 22, protocol: "tcp" }],
        [:forwarded_port, { host: 8080, guest: 80, protocol: "tcp", host_ip: "", guest_ip: "" }],
      ])
      allow(ctx[:driver]).to receive(:start)

      action = described_class.new(app, ctx[:env])
      ports = action.forwarded_ports(ctx[:env])

      expect(ports.length).to eq 1
      expect(ports.first).to include("8080")
    end

    it "skips disabled ports" do
      ctx = mock_vagrant_env(networks: [
        [:forwarded_port, { host: 8080, guest: 80, disabled: true, protocol: "tcp", host_ip: "", guest_ip: "" }],
      ])

      action = described_class.new(app, ctx[:env])
      ports = action.forwarded_ports(ctx[:env])

      expect(ports).to be_empty
    end
  end
end
