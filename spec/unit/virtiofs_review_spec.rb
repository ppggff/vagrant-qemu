require "spec_helper"
require "vagrant-qemu/synced_folder_virtiofs"
require "vagrant-qemu/action/mount_virtiofs"
require "vagrant-qemu/action/reset_virtiofs_args"

describe "VirtioFS review regressions" do
  around do |example|
    with_temp_dir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:config) do
    VagrantPlugins::QEMU::Config.new.tap do |c|
      c.arch = "x86_64"
      c.virtiofsd_bin = "virtiofsd"
      c.finalize!
    end
  end
  let(:ui) { double("ui", info: nil, error: nil) }
  let(:communicator) { double("communicator", sudo: nil) }
  let(:driver) { double("driver", running?: false) }
  let(:machine) do
    double("machine", provider_name: :qemu, provider_config: config,
      provider: double("provider", driver: driver), data_dir: @dir,
      id: "review123", ui: ui, communicate: communicator)
  end
  let(:adapter) { VagrantPlugins::QEMU::SyncedFolderVirtioFS.new }

  before do
    allow(Process).to receive(:kill).and_return(1)
    allow(Vagrant::Util::Which).to receive(:which).with("virtiofsd").and_return("virtiofsd")
    allow(File).to receive(:executable?).with("virtiofsd").and_return(true)
    allow(File).to receive(:file?).with("virtiofsd").and_return(true)
    allow(Open3).to receive(:capture2e).and_return(["", double("status", success?: true)])
    allow(Open3).to receive(:capture2e).with("qemu-system-x86_64", "-device", "help")
      .and_return(["name \"vhost-user-fs-pci\"", double("status", success?: true)])
  end

  it "rejects an explicit daemon path that cannot be executed" do
    config.virtiofsd_bin = "/missing/virtiofsd"
    allow(Vagrant::Util::Which).to receive(:which).with(config.virtiofsd_bin).and_return(nil)
    expect(adapter.usable?(machine)).to eq(false)
  end

  it "rejects QEMU without the vhost-user-fs-pci device before spawning" do
    allow(Open3).to receive(:capture2e).with("qemu-system-x86_64", "-device", "help")
      .and_return(["name \"virtio-net-pci\"", double("status", success?: true)])
    expect(adapter.usable?(machine)).to eq(false)
  end

  it "rounds fractional memory to a whole MiB for the shared backend" do
    expect(adapter.send(:normalized_memory, "1.3G")).to eq("1332M")
  end

  it "ignores a stale mount map when this start prepared no shares" do
    FileUtils.mkdir_p(@dir.join("virtiofs"))
    File.write(@dir.join("virtiofs/mounts.json"), JSON.generate("virtiofs0" => "/stale"))
    app = double("app", call: nil)
    VagrantPlugins::QEMU::Action::MountVirtioFS.new(app, {}).call(machine: machine)
    expect(communicator).not_to have_received(:sudo)
    expect(app).to have_received(:call)
  end

  ["", "0", "-1", "not-a-pid"].each do |contents|
    it "never signals invalid saved PID #{contents.inspect}" do
      FileUtils.mkdir_p(@dir.join("virtiofs"))
      File.write(@dir.join("virtiofs/virtiofs0.pid"), contents)
      adapter.cleanup(machine, {})
      expect(Process).not_to have_received(:kill)
    end
  end

  it "does not signal a PID now belonging to another user process" do
    FileUtils.mkdir_p(@dir.join("virtiofs"))
    File.write(@dir.join("virtiofs/virtiofs0.pid"), "12345")
    File.write(@dir.join("virtiofs/virtiofs0.sock_path"), "/tmp/review.sock")
    allow(Open3).to receive(:capture2e).and_return([
      "Mon Oct 12 12:00:00 2026 ruby unrelated-script.rb", double("status", success?: true)
    ])
    adapter.cleanup(machine, {})
    expect(Process).not_to have_received(:kill).with("TERM", 12345)
    expect(Process).not_to have_received(:kill).with("KILL", 12345)
  end

  it "does not fail cleanup for a saved PID with EPERM" do
    FileUtils.mkdir_p(@dir.join("virtiofs"))
    File.write(@dir.join("virtiofs/virtiofs0.pid"), "12345")
    allow(Process).to receive(:kill).with(anything, 12345).and_raise(Errno::EPERM)
    expect { adapter.cleanup(machine, {}) }.not_to raise_error
    expect(Process).not_to have_received(:kill).with("TERM", 12345)
  end
end
