require "spec_helper"

describe VagrantPlugins::QEMU::Action::ReadState do
  let(:app) { double("app", call: nil) }

  it "sets :not_created when no machine id" do
    ctx = mock_vagrant_env
    allow(ctx[:machine]).to receive(:id).and_return(nil)

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:env][:machine_state_id]).to eq :not_created
  end

  it "updates driver.ssh_port when running" do
    ctx = mock_vagrant_env
    allow(ctx[:machine]).to receive(:id).and_return("vq_test123")
    allow(ctx[:driver]).to receive(:get_current_state).and_return(:running)
    allow(ctx[:driver]).to receive(:get_ssh_port).with(50022).and_return(50023)

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:driver]).to have_received(:get_ssh_port).with(50022)
  end

  it "clears stale id when not_created" do
    ctx = mock_vagrant_env
    allow(ctx[:machine]).to receive(:id).and_return("vq_stale")
    allow(ctx[:driver]).to receive(:get_current_state).and_return(:not_created)

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:machine]).to have_received(:id=).with(nil)
  end

  it "does not modify provider_config.ssh_port" do
    ctx = mock_vagrant_env
    allow(ctx[:machine]).to receive(:id).and_return("vq_test123")
    allow(ctx[:driver]).to receive(:get_current_state).and_return(:running)
    allow(ctx[:driver]).to receive(:get_ssh_port).and_return(50099)

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:config].ssh_port).to eq 50022
  end
end
