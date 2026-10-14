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

    expect(ctx[:vm_config]).to have_received(:network).with(
      :forwarded_port, hash_including(id: "ssh", host: 50022)
    )
    expect(ssh_entry[:host]).to eq 2222
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

    expect(ctx[:vm_config]).to have_received(:network).with(
      :forwarded_port, hash_including(id: "ssh", auto_correct: true)
    )
  end

  it "sets auto_correct=false when ssh_auto_correct is false" do
    ssh_entry = { id: "ssh", host: 50022, guest: 22, auto_correct: true }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_auto_correct: false },
      networks: [[:forwarded_port, ssh_entry]]
    )

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:vm_config]).to have_received(:network).with(
      :forwarded_port, hash_including(id: "ssh", auto_correct: false)
    )
  end

  it "uses custom ssh_port" do
    ssh_entry = { id: "ssh", host: 2222, guest: 22, auto_correct: false }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 60022 },
      networks: [[:forwarded_port, ssh_entry]]
    )

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:vm_config]).to have_received(:network).with(
      :forwarded_port, hash_including(id: "ssh", host: 60022)
    )
  end

  describe "an SSH rule shared by several machines" do
    # Vagrant merges each machine's config from the same top-level config, so
    # a forwarded_port declared there is one options hash shared by all of
    # them. Updating it in place would leak into the other machines.
    def shared_vm_configs
      require Vagrant.source_root.join("plugins/kernel_v2/config/vm").to_s
      root = VagrantPlugins::Kernel_V2::VMConfig.new
      root.network :forwarded_port, id: "ssh", guest: 22, host: 2222
      Array.new(2) { root.merge(VagrantPlugins::Kernel_V2::VMConfig.new) }
    end

    def ssh_rule(vm_config)
      vm_config.networks.find { |type, options| type == :forwarded_port && options[:id] == "ssh" }[1]
    end

    def run_on(vm_config, **overrides)
      ctx = mock_vagrant_env(provider_config_overrides: overrides)
      allow(ctx[:machine]).to receive(:config).and_return(double("config", vm: vm_config))
      described_class.new(app, ctx[:env]).call(ctx[:env])
    end

    it "disables the rule only for the machine without the default NIC" do
      mine, other = shared_vm_configs
      run_on(mine, net_device: nil)
      expect(ssh_rule(mine)[:disabled]).to eq true
      expect(ssh_rule(other)).not_to include(:disabled)
    end

    it "sets the host port only for the machine being started" do
      mine, other = shared_vm_configs
      run_on(mine, ssh_port: 50023, ssh_auto_correct: true)
      expect(ssh_rule(mine)).to include(host: 50023, auto_correct: true)
      expect(ssh_rule(other)).to include(host: 2222)
      expect(ssh_rule(other)).not_to include(:auto_correct)
    end
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
  describe "direct SSH with the default NIC disabled" do
    it "keeps the platform port check for user forwards without auto-correction" do
      allow(Vagrant::Util::Platform).to receive(:windows?).and_return(false)
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close
      ctx = mock_vagrant_env(provider_config_overrides: { net_device: nil },
        networks: [[:forwarded_port, { guest: 80, host: port, auto_correct: false }]])

      described_class.new(app, ctx[:env]).call(ctx[:env])

      expect(ctx[:env].fetch(:port_collision_port_check).call("127.0.0.1", port)).to eq false
      expect(ctx[:env][:port_collision_remap]).to eq({})
      expect(ctx[:env][:port_collision_extra_in_use]).to eq({})
    ensure
      server&.close
    end
    it "does not add a synthetic SSH forwarding rule" do
      ctx = mock_vagrant_env(provider_config_overrides: { net_device: nil, ssh_port: 22, ssh_auto_correct: true })
      VagrantPlugins::QEMU::Action::PrepareForwardedPortCollisionParams.new(app, ctx[:env]).call(ctx[:env])
      expect(ctx[:vm_config]).not_to have_received(:network)
      expect(app).to have_received(:call).with(ctx[:env])
    end

    it "disables an inherited SSH forward without changing user forwards" do
      ssh = { id: "ssh", host: 2222, guest: 22 }
      web = { guest: 80, host: 8080 }
      ctx = mock_vagrant_env(provider_config_overrides: { net_device: nil },
        networks: [[:forwarded_port, ssh], [:forwarded_port, web]])
      VagrantPlugins::QEMU::Action::PrepareForwardedPortCollisionParams.new(app, ctx[:env]).call(ctx[:env])
      expect(ctx[:vm_config]).to have_received(:network).with(:forwarded_port, id: "ssh", disabled: true)
      expect(ssh).to eq(id: "ssh", host: 2222, guest: 22)
      expect(web).to eq(guest: 80, host: 8080)
    end

  end

end
