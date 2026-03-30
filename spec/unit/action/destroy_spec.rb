require "spec_helper"

describe VagrantPlugins::QEMU::Action::Destroy do
  let(:app) { double("app", call: nil) }

  it "clears machine id after successful delete" do
    ctx = mock_vagrant_env
    allow(ctx[:driver]).to receive(:delete)

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(ctx[:driver]).to have_received(:delete)
    expect(ctx[:machine]).to have_received(:id=).with(nil)
  end

  it "preserves machine id when delete fails" do
    ctx = mock_vagrant_env
    allow(ctx[:driver]).to receive(:delete).and_raise(Errno::EACCES, "permission denied")

    action = described_class.new(app, ctx[:env])
    expect { action.call(ctx[:env]) }.to raise_error(VagrantPlugins::QEMU::Errors::VagrantQEMUError)
    expect(ctx[:machine]).not_to have_received(:id=)
  end

  it "raises VagrantQEMUError on failure" do
    ctx = mock_vagrant_env
    allow(ctx[:driver]).to receive(:delete).and_raise(RuntimeError, "boom")

    action = described_class.new(app, ctx[:env])
    expect { action.call(ctx[:env]) }.to raise_error(
      VagrantPlugins::QEMU::Errors::VagrantQEMUError
    )
  end
end
