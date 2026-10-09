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

  describe "port collision check" do
    def port_check(windows: false)
      allow(Vagrant::Util::Platform).to receive(:windows?).and_return(windows)
      ctx = mock_vagrant_env(networks: [])
      described_class.new(app, ctx[:env]).call(ctx[:env])
      ctx[:env][:port_collision_port_check]
    end

    it "reports a listening port as in use" do
      server = TCPServer.new("127.0.0.1", 0)
      expect(port_check.call("127.0.0.1", server.addr[1])).to eq true
    ensure
      server&.close
    end

    it "reports a closed port as free" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close
      expect(port_check.call("127.0.0.1", port)).to eq false
    end

    it "checks 0.0.0.0 when no host_ip is given" do
      expect(described_class).to receive(:port_in_use?).with("0.0.0.0", 50022).and_return(false)
      port_check.call(nil, 50022)
    end

    it "keeps Vagrant's own check on Windows" do
      expect(port_check(windows: true)).to be_nil
    end
  end
end
