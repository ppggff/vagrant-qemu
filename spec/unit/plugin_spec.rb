require "spec_helper"

describe VagrantPlugins::QEMU::Plugin do
  it "selects canonical qemu boxes without a libvirt alias" do
    _provider, options = described_class.components.providers.get(:qemu)
    expect(options.fetch(:box_format)).to eq("qemu")
  end
end
