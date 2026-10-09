require "spec_helper"
require "json"
require "vagrant-qemu/action/export"

describe VagrantPlugins::QEMU::Action::Export do
  let(:vm_id) { "vq_export" }
  let(:app) { lambda { |env| } }
  let(:ui) { double("ui", info: nil, detail: nil) }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      @tmp_base = dir.join("tmp")
      @export_dir = dir.join("export")
      FileUtils.mkdir_p(@data_dir.join(vm_id))
      FileUtils.mkdir_p(@tmp_base)
      FileUtils.mkdir_p(@export_dir)
      example.run
    end
  end

  let(:driver) { VagrantPlugins::QEMU::Driver.new(vm_id, @data_dir, @tmp_base) }
  let(:provider) { double("provider", driver: driver) }
  let(:state) { double("state", id: :stopped) }
  let(:machine) do
    c = VagrantPlugins::QEMU::Config.new
    c.arch = "aarch64"
    c.finalize!
    double("machine", provider: provider, provider_config: c, name: "default", state: state)
  end
  let(:env) { { machine: machine, ui: ui, "export.temp_dir" => @export_dir.to_s } }

  before do
    VagrantPlugins::QEMU::Plugin.setup_i18n
    # Don't invoke real qemu-img convert; just record calls.
    allow(driver).to receive(:convert_box_disk)
    # virtual-size from qemu-img info: 1 GiB + 1 byte → ceil to 2 GB.
    status = double("status", success?: true)
    allow(Open3).to receive(:capture3)
      .and_return([JSON.generate("virtual-size" => (1024**3) + 1), "", status])
  end

  def metadata
    JSON.parse(File.read(@export_dir.join("metadata.json")))
  end

  context "single box disk (v1)" do
    before { FileUtils.touch(@data_dir.join(vm_id, "linked-box.img")) }

    it "flattens the disk to box.img and writes canonical qemu v1 metadata (no disks[])" do
      expect(driver).to receive(:convert_box_disk)
        .with(@data_dir.join(vm_id, "linked-box.img"), @export_dir.join("box.img"))
      described_class.new(app, env).call(env)

      expect(metadata["provider"]).to eq "qemu"
      expect(metadata["format"]).to eq "qcow2"
      expect(metadata["virtual_size"]).to eq 2
      expect(metadata).not_to have_key("disks")
    end
  end

  context "multiple box disks (v2)" do
    before do
      %w[linked-box.img linked-box-1.img].each { |n| FileUtils.touch(@data_dir.join(vm_id, n)) }
    end

    it "flattens each disk to box_N.img and writes disks[]" do
      expect(driver).to receive(:convert_box_disk)
        .with(@data_dir.join(vm_id, "linked-box.img"), @export_dir.join("box_1.img"))
      expect(driver).to receive(:convert_box_disk)
        .with(@data_dir.join(vm_id, "linked-box-1.img"), @export_dir.join("box_2.img"))
      described_class.new(app, env).call(env)

      expect(metadata["disks"]).to eq([{ "path" => "box_1.img" }, { "path" => "box_2.img" }])
      expect(metadata["provider"]).to eq "qemu"
    end
  end

  context "environment-specific artifacts present" do
    before do
      FileUtils.touch(@data_dir.join(vm_id, "linked-box.img"))
      FileUtils.touch(@data_dir.join(vm_id, "extra-data.qcow2"))
      FileUtils.touch(@data_dir.join(vm_id, "vagrant-qemu-network.iso"))
    end

    it "packages only the box disk, not additional disks or ISOs" do
      expect(driver).to receive(:convert_box_disk).once
        .with(@data_dir.join(vm_id, "linked-box.img"), @export_dir.join("box.img"))
      described_class.new(app, env).call(env)
      expect(metadata).not_to have_key("disks")
    end
  end

  context "VM not powered off" do
    let(:state) { double("state", id: :running) }
    before { FileUtils.touch(@data_dir.join(vm_id, "linked-box.img")) }

    it "raises and does not convert" do
      expect(driver).not_to receive(:convert_box_disk)
      expect { described_class.new(app, env).call(env) }
        .to raise_error(Vagrant::Errors::VMPowerOffToPackage)
    end
  end
end
