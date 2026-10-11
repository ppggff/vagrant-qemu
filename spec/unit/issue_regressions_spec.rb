require "spec_helper"

describe "open issue regressions" do
  let(:app) { double("app", call: nil) }

  describe "direct SSH with the default NIC disabled (#71)" do
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
      expect(ssh[:disabled]).to eq true
      expect(web).to eq(guest: 80, host: 8080)
    end

    it "ignores an inherited corrected SSH port when there is no provider NIC" do
      ctx = mock_vagrant_env(provider_config_overrides: { net_device: nil, ssh_port: 22 },
        networks: [[:forwarded_port, { id: "ssh", host: 2200, guest: 22 }]])
      options = nil
      allow(ctx[:driver]).to receive(:start) { |opts| options = opts }
      VagrantPlugins::QEMU::Action::StartInstance.new(app, ctx[:env]).call(ctx[:env])
      expect(options[:ssh_port]).to eq 22
    end
  end


end
