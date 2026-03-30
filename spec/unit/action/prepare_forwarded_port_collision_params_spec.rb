require "spec_helper"

describe VagrantPlugins::QEMU::Action::PrepareForwardedPortCollisionParams do
  let(:app) { double("app", call: nil) }

  it "updates existing SSH forwarded_port host to ssh_port" do
    ssh_entry = { id: "ssh", host: 2222, guest: 22, auto_correct: false }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 50022 },
      networks: [[:forwarded_port, ssh_entry]]
    )

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ssh_entry[:host]).to eq 50022
  end

  it "creates SSH forwarded_port when not present" do
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 50022 },
      networks: []
    )

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:vm_config]).to have_received(:network).with(
      :forwarded_port,
      hash_including(guest: 22, host: 50022, id: "ssh", protocol: "tcp")
    )
  end

  it "sets auto_correct=true when ssh_auto_correct is true" do
    ssh_entry = { id: "ssh", host: 50022, guest: 22, auto_correct: false }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_auto_correct: true },
      networks: [[:forwarded_port, ssh_entry]]
    )

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ssh_entry[:auto_correct]).to eq true
  end

  it "sets auto_correct=false when ssh_auto_correct is false" do
    ssh_entry = { id: "ssh", host: 50022, guest: 22, auto_correct: true }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_auto_correct: false },
      networks: [[:forwarded_port, ssh_entry]]
    )

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ssh_entry[:auto_correct]).to eq false
  end

  it "uses custom ssh_port" do
    ssh_entry = { id: "ssh", host: 2222, guest: 22, auto_correct: false }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 60022 },
      networks: [[:forwarded_port, ssh_entry]]
    )

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ssh_entry[:host]).to eq 60022
  end
end
