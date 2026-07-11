require "spec_helper"

describe VagrantPlugins::QEMU::Action, "#action_package" do
  it "returns a runnable builder instead of raising NotSupportedError" do
    expect(described_class.action_package).to be_a(Vagrant::Action::Builder)
  end

  it "no longer raises (package is supported now)" do
    expect { described_class.action_package }.not_to raise_error
  end

  it "validates config and branches on machine state at the top of the chain" do
    klasses = described_class.action_package.stack.map(&:first)
    expect(klasses).to include(Vagrant::Action::Builtin::ConfigValidate)
    expect(klasses).to include(Vagrant::Action::Builtin::Call)
  end

  it "autoloads the Export and PackageVagrantfile actions" do
    expect { described_class::Export }.not_to raise_error
    expect { described_class::PackageVagrantfile }.not_to raise_error
  end
end
