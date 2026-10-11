require "spec_helper"

describe "cleanup of a newly launched VM after boot failure" do
  let(:ctx) { mock_vagrant_env(provider_config_overrides: { control_port: 33333 }) }
  let(:driver) { ctx[:driver] }

  before do
    allow(driver).to receive(:start)
    allow(driver).to receive(:stop)
  end

  def run_with_failure(error)
    builder = Vagrant::Action::Builder.new
    builder.use VagrantPlugins::QEMU::Action::StartInstance
    builder.use ->(_env) { raise error }
    builder.call(ctx[:env])
  end

  it "stops QEMU when Vagrant's communicator boot wait times out" do
    expect { run_with_failure(Vagrant::Errors::VMBootTimeout.new) }.to raise_error(Vagrant::Errors::VMBootTimeout)
    expect(driver).to have_received(:stop).with(control_port: 33333, graceful_timeout: 1)
  end

  it "stops QEMU if Vagrant reports an invalid boot state" do
    error = Vagrant::Errors::VMBootBadState.new(valid: "running", invalid: "stopped")
    expect { run_with_failure(error) }.to raise_error(Vagrant::Errors::VMBootBadState)
    expect(driver).to have_received(:stop)
  end

  it "preserves the original boot failure if cleanup also fails" do
    allow(driver).to receive(:stop).and_raise(RuntimeError, "monitor unavailable")
    expect { run_with_failure(Vagrant::Errors::VMBootTimeout.new) }.to raise_error(Vagrant::Errors::VMBootTimeout)
    expect(driver).to have_received(:stop)
  end

  it "leaves a VM available for debugging after a provisioning error" do
    expect { run_with_failure(RuntimeError.new("provisioner failed")) }.to raise_error(RuntimeError, "provisioner failed")
    expect(driver).not_to have_received(:stop)
  end

  it "does not stop a VM when the QEMU launch never completed" do
    allow(driver).to receive(:start).and_raise(RuntimeError, "launch failed")
    expect { run_with_failure(Vagrant::Errors::VMBootTimeout.new) }.to raise_error(RuntimeError, "launch failed")
    expect(driver).not_to have_received(:stop)
  end
end
