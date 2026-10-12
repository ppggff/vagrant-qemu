require "spec_helper"
require "json"
require "vagrant-qemu/synced_folder_virtiofs"
require "vagrant-qemu/action/mount_virtiofs"
require "vagrant-qemu/action/cleanup_virtiofs"

describe VagrantPlugins::QEMU::SyncedFolderVirtioFS do
  around do |example|
    with_temp_dir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:config) do
    VagrantPlugins::QEMU::Config.new.tap do |config|
      config.virtiofsd_bin = "virtiofsd"
      config.memory = "256M"
      config.extra_virtiofsd_args = ["--cache=always"]
      config.finalize!
    end
  end
  let(:ui) { double("ui", info: nil, error: nil) }
  let(:communicator) { double("communicator", sudo: nil) }
  let(:machine) do
    double("machine", provider_config: config, data_dir: @dir.join("machine"),
      id: "test123", ui: ui, communicate: communicator)
  end
  let(:folders) do
    { "share" => { hostpath: @dir.join("host share").to_s, guestpath: "/mnt/a shared folder" } }
  end
  subject(:adapter) { described_class.new }

  before do
    allow(Process).to receive(:uid).and_return(1000)
    allow(Process).to receive(:gid).and_return(1000)
    allow(adapter).to receive(:virtiofsd_help).and_return("--translate-uid --translate-gid")
    allow(adapter).to receive(:spawn).and_return(12345)
    allow(Process).to receive(:detach).with(12345).and_return(double("waiter"))
    allow(Process).to receive(:kill).with(anything, 12345).and_return(1)
    allow(adapter).to receive(:process_alive?).with(12345).and_return(true)
    allow(adapter).to receive(:process_identity).with(12345).and_return(
      "Mon Oct 12 12:00:00 2026 virtiofsd --socket-path=#{File.join(Dir.tmpdir, 'vqemu-test123-virtiofs0.sock')}")
    allow(File).to receive(:socket?).and_return(true)
    allow(adapter).to receive(:sleep)
  end

  it "passes daemon arguments and uses a directory for shared guest RAM" do
    adapter.prepare(machine, folders, {})
    expect(adapter).to have_received(:spawn).with(
      "virtiofsd", "--socket-path=#{File.join(Dir.tmpdir, 'vqemu-test123-virtiofs0.sock')}",
      "--shared-dir=#{folders['share'][:hostpath]}", "--sandbox=none", "--inode-file-handles=never",
      "--translate-uid", "map:1000:#{Process.uid}:1",
      "--translate-gid", "map:1000:#{Process.gid}:1", "--cache=always", anything)
    expect(config.virtiofs_qemu_args).to include(
      "memory-backend-file,id=mem,size=256M,mem-path=#{Dir.tmpdir},share=on",
      "vhost-user-fs-pci,chardev=char_virtiofs0,tag=virtiofs0")
  end

  { 2048 => "2048M", "2048" => "2048M", "0.5g" => "512M", "1024K" => "1M" }.each do |input, expected|
    it "normalizes qe.memory #{input.inspect} to #{expected}" do
      config.memory = input
      adapter.prepare(machine, folders, {})
      expect(config.virtiofs_qemu_args.join(" ")).to include("size=#{expected},")
    end
  end

  [nil, 0, -1, "invalid", "1G,share=off"].each do |input|
    it "rejects qe.memory #{input.inspect} before starting a daemon" do
      config.memory = input
      expect { adapter.prepare(machine, folders, {}) }.to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
      expect(adapter).not_to have_received(:spawn)
    end
  end

  it "replaces the QEMU arguments and resolved mount mapping on reload" do
    adapter.prepare(machine, folders, {})
    adapter.prepare(machine, { "other" => { hostpath: @dir.to_s, guestpath: "/mnt/other" } }, {})
    expect(config.virtiofs_qemu_args.count { |arg| arg.start_with?("memory-backend-file,") }).to eq(1)
    expect(JSON.parse(File.read(machine.data_dir.join("virtiofs/mounts.json")))).to eq("virtiofs0" => "/mnt/other")
    expect(Process).to have_received(:kill).with("TERM", 12345)
  end

  it "mounts the prepared folder mapping without re-reading raw folder types" do
    adapter.prepare(machine, folders.merge("implicit" => { hostpath: @dir.to_s, guestpath: "/aaa" }), {})
    app = double("app", call: nil)
    VagrantPlugins::QEMU::Action::MountVirtioFS.new(app, {}).call(machine: machine)
    expect(communicator).to have_received(:sudo).with("mount -t virtiofs virtiofs0 /aaa")
    expect(communicator).to have_received(:sudo).with("mkdir -p /mnt/a\\ shared\\ folder")
    expect(communicator).to have_received(:sudo).with("mount -t virtiofs virtiofs1 /mnt/a\\ shared\\ folder")
    expect(app).to have_received(:call)
  end

  it "cleans every daemon before removing its bookkeeping" do
    adapter.prepare(machine, folders, {})
    adapter.cleanup(machine, {})
    expect(Process).to have_received(:kill).with("TERM", 12345)
    expect(machine.data_dir.join("virtiofs")).not_to exist
  end

  it "stops a failed daemon and removes its incomplete mount mapping" do
    allow(adapter).to receive(:process_alive?).and_return(false)
    allow(Process).to receive(:detach).and_return(double("waiter", value: "failed"))
    allow(adapter).to receive(:spawn) do
      File.write(machine.data_dir.join("virtiofs/virtiofs0.log"), "failed startup")
      12345
    end
    expect { adapter.prepare(machine, folders, {}) }.to raise_error(VagrantPlugins::QEMU::Errors::VirtiofsdStartFailed)
    expect(Process).to have_received(:kill).with("TERM", 12345).at_least(:once)
    expect(Dir.glob(machine.data_dir.join("virtiofs/*.pid"))).to be_empty
    expect(machine.data_dir.join("virtiofs/mounts.json")).not_to exist
    expect(File.read(machine.data_dir.join("virtiofs/virtiofs0.log"))).to eq("failed startup")
    expect(config.virtiofs_qemu_args).to eq([])
  end
end

describe "VirtioFS destroy action ordering" do
  [:halt, :package].each do |command|
    it "wires daemon cleanup after stopping QEMU for #{command}" do
      actions = VagrantPlugins::QEMU::Action
      root = double("root builder", use: nil)
      created = double("created builder", use: nil)
      allow(Vagrant::Action::Builder).to receive(:new).and_return(root)
      expect(root).to receive(:use).with(actions::Call, actions::IsState, :not_created)
        .and_yield({ result: false }, created)
      expect(created).to receive(:use).with(actions::StopInstance).ordered
      expect(created).to receive(:use).with(actions::CleanupVirtioFS).ordered
      actions.public_send("action_#{command}")
    end
  end

  it "wires daemon cleanup before Destroy can clear machine.id and data_dir" do
    actions = VagrantPlugins::QEMU::Action
    root = double("root builder")
    confirmed = double("confirmed builder")
    created = double("created builder", use: nil)
    allow(Vagrant::Action::Builder).to receive(:new).and_return(root)
    expect(root).to receive(:use).with(actions::Call, actions::DestroyConfirm)
      .and_yield({ result: true }, confirmed)
    expect(confirmed).to receive(:use).with(actions::ConfigValidate)
    expect(confirmed).to receive(:use).with(actions::Call, actions::IsState, :not_created)
      .and_yield({ result: false }, created)
    expect(created).to receive(:use).with(actions::StopInstance).ordered
    expect(created).to receive(:use).with(actions::CleanupVirtioFS).ordered
    expect(created).to receive(:use).with(actions::Destroy).ordered
    actions.action_destroy
  end
end

describe VagrantPlugins::QEMU::Action::CleanupVirtioFS do
  it "stops VirtioFS before the downstream action clears machine data" do
    machine = double("machine")
    adapter = instance_double(VagrantPlugins::QEMU::SyncedFolderVirtioFS)
    allow(VagrantPlugins::QEMU::SyncedFolderVirtioFS).to receive(:new).and_return(adapter)
    app = double("app")
    expect(adapter).to receive(:cleanup).with(machine, {}).ordered
    expect(app).to receive(:call).with({ machine: machine }).ordered
    described_class.new(app, {}).call(machine: machine)
  end
end
