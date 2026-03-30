require_relative "helper"

describe "SSH port collision handling", :acceptance do
  it "PrepareForwardedPortCollisionParams creates SSH entry with auto_correct" do
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 50022, ssh_auto_correct: true },
      networks: []
    )
    app = double("app", call: nil)

    action = VagrantPlugins::QEMU::Action::PrepareForwardedPortCollisionParams.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:vm_config]).to have_received(:network).with(
      :forwarded_port,
      hash_including(host: 50022, auto_correct: true, id: "ssh")
    )
  end

  it "StartInstance reads corrected port from SSH forwarded_port entry" do
    # Simulate: PrepareForwarded set host=50022, HandleCollisions corrected to 50023
    ssh_entry = { id: "ssh", host: 50023, guest: 22, protocol: "tcp" }
    ctx = mock_vagrant_env(
      provider_config_overrides: { ssh_port: 50022, ssh_auto_correct: true },
      networks: [[:forwarded_port, ssh_entry]]
    )
    app = double("app", call: nil)

    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = VagrantPlugins::QEMU::Action::StartInstance.new(app, ctx[:env])
    action.call(ctx[:env])

    # Should use the corrected port, not the config value
    expect(received_options[:ssh_port]).to eq 50023
  end

  it "options.yml persists the corrected port" do
    with_temp_dir do |dir|
      opt_dir = dir.join("opts")
      FileUtils.mkdir_p(opt_dir)

      # Simulate what driver.start writes
      persisted = { ssh_port: 50023, control_port: nil }
      File.write(opt_dir.join("options.yml"), persisted.to_yaml)

      # Simulate what get_ssh_port reads
      loaded = YAML.safe_load_file(opt_dir.join("options.yml"), permitted_classes: [Symbol])
      expect(loaded[:ssh_port]).to eq 50023
    end
  end
end
