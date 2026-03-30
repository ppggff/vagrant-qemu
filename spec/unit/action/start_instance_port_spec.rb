require "spec_helper"

describe VagrantPlugins::QEMU::Action::StartInstance, "SSH port collision readback" do
  let(:app) { double("app", call: nil) }

  it "uses config ssh_port when no collision" do
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 50022 },
      networks: [[:forwarded_port, { id: "ssh", host: 50022, guest: 22, protocol: "tcp" }]]
    )
    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(received_options[:ssh_port]).to eq 50022
  end

  it "picks up corrected port from SSH forwarded_port entry" do
    # Simulate HandleForwardedPortCollisions having changed host to 50023
    ssh_entry = { id: "ssh", host: 50023, guest: 22, protocol: "tcp" }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 50022 },
      networks: [[:forwarded_port, ssh_entry]]
    )
    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(received_options[:ssh_port]).to eq 50023
  end

  it "falls back to config value when no SSH entry exists" do
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 50022 },
      networks: []
    )
    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(received_options[:ssh_port]).to eq 50022
  end

  it "persists the corrected port in options.yml" do
    ssh_entry = { id: "ssh", host: 50023, guest: 22, protocol: "tcp" }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 50022 },
      networks: [[:forwarded_port, ssh_entry]]
    )
    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(received_options[:ssh_port]).to eq 50023
  end

  it "forwarded_ports excludes SSH entry" do
    ctx = mock_vagrant_env(networks: [
      [:forwarded_port, { id: "ssh", host: 50022, guest: 22, protocol: "tcp" }],
      [:forwarded_port, { host: 8080, guest: 80, protocol: "tcp", host_ip: "", guest_ip: "" }],
    ])

    action = described_class.new(app, ctx[:env])
    ports = action.forwarded_ports(ctx[:env])

    expect(ports.length).to eq 1
    expect(ports.none? { |p| p.include?("50022") }).to eq true
  end
end
