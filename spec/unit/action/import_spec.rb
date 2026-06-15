require "spec_helper"
require "vagrant-qemu/action/import"

describe VagrantPlugins::QEMU::Action::Import, "qemu_dir validation" do
  let(:app) { lambda { |env| } }
  let(:ui) { double("ui", output: nil, detail: nil) }
  let(:driver) { double("driver", import: { id: "vq_imported" }) }
  let(:provider) { double("provider", driver: driver) }
  let(:machine) { double("machine", name: "default", provider: provider) }

  # A real Config so provider_config.arch/qemu_dir/etc. behave like production.
  def config_with(arch:, qemu_dir:, image:)
    c = VagrantPlugins::QEMU::Config.new
    c.arch = arch
    c.qemu_dir = qemu_dir
    c.image_path = image
    c.finalize!
    c
  end

  around(:each) do |example|
    with_temp_dir do |dir|
      @img = dir.join("box.img")
      FileUtils.touch(@img)
      example.run
    end
  end

  before do
    VagrantPlugins::QEMU::Plugin.setup_i18n
    allow(machine).to receive(:id=)
    # Avoid invoking the real qemu-img binary.
    status = double("status", success?: true)
    allow(Open3).to receive(:capture3).and_return(['{"format":"qcow2"}', "", status])
  end

  def run(arch:, qemu_dir:)
    allow(machine).to receive(:provider_config)
      .and_return(config_with(arch: arch, qemu_dir: qemu_dir, image: @img.to_s))
    env = { machine: machine, ui: ui }
    described_class.new(app, env).call(env)
  end

  it "does not require qemu_dir for x86_64 (boots on SeaBIOS)" do
    expect { run(arch: "x86_64", qemu_dir: "/definitely/not/here") }.not_to raise_error
  end

  it "still requires a valid qemu_dir for aarch64 firmware" do
    expect { run(arch: "aarch64", qemu_dir: "/definitely/not/here") }
      .to raise_error(VagrantPlugins::QEMU::Errors::ConfigError, /Invalid qemu dir/)
  end
end
