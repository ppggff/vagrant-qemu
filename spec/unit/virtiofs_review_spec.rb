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
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with("virtiofsd").and_return(true)
    allow(File).to receive(:file?).and_call_original
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
    File.write(@dir.join("virtiofs/virtiofs0.sock_path"), "/tmp/review.sock")
    allow(Process).to receive(:kill).with(anything, 12345).and_raise(Errno::EPERM)
    expect { adapter.cleanup(machine, {}) }.not_to raise_error
    expect(Process).not_to have_received(:kill).with("TERM", 12345)
  end

  it "does not signal a reused PID even with the same daemon command" do
    FileUtils.mkdir_p(@dir.join("virtiofs"))
    File.write(@dir.join("virtiofs/virtiofs0.pid"), "12345")
    File.write(@dir.join("virtiofs/virtiofs0.sock_path"), "/tmp/review.sock")
    File.write(@dir.join("virtiofs/virtiofs0.process.json"), JSON.generate(
      "identity" => "Mon Oct 12 11:00:00 2026 virtiofsd --socket-path=/tmp/review.sock", "binary" => "virtiofsd"))
    allow(Open3).to receive(:capture2e).and_return([
      "Mon Oct 12 12:00:00 2026 virtiofsd --socket-path=/tmp/review.sock", double("status", success?: true)
    ])
    adapter.cleanup(machine, {})
    expect(Process).not_to have_received(:kill).with("TERM", 12345)
  end

  it "cleans old maps even when the new start has no VirtioFS folders" do
    FileUtils.mkdir_p(@dir.join("virtiofs"))
    File.write(@dir.join("virtiofs/mounts.json"), '{}')
    VagrantPlugins::QEMU::Action::ResetVirtioFSArgs.new(double("app", call: nil), {}).call(machine: machine)
    expect(@dir.join("virtiofs")).not_to exist
    expect(config.virtiofs_qemu_args).to eq([])
  end

  [false, true].each do |running|
    it "#{running ? 'preserves' : 'cleans'} daemons when failed-start recovery leaves QEMU #{running ? 'running' : 'stopped'}" do
      allow(driver).to receive(:running?).and_return(running)
      error = RuntimeError.new("boot failed")
      app = double("app")
      allow(app).to receive(:call) do
        FileUtils.mkdir_p(@dir.join("virtiofs"))
        File.write(@dir.join("virtiofs/mounts.json"), '{}')
        File.write(@dir.join("virtiofs/virtiofs0.log"), 'diagnostic')
        config.virtiofs_qemu_args = ["-device", "vhost-user-fs-pci"]
        raise error
      end
      action = VagrantPlugins::QEMU::Action::ResetVirtioFSArgs.new(app, {})
      expect { action.call(machine: machine) }.to raise_error(error)
      action.recover(machine: machine)
      expect(@dir.join("virtiofs/mounts.json").exist?).to eq(running)
      expect(File.read(@dir.join("virtiofs/virtiofs0.log"))).to eq('diagnostic')
    end
  end

  [false, true].each do |shown|
    it "#{shown ? 'does not repeat' : 'prints'} daemon logs on recovery when StartInstance #{shown ? 'already printed' : 'did not print'} them" do
      app = double("app")
      allow(app).to receive(:call) do
        FileUtils.mkdir_p(@dir.join("virtiofs"))
        File.write(@dir.join("virtiofs/virtiofs0.log"), 'diagnostic')
        config.virtiofs_qemu_args = ["-device", "vhost-user-fs-pci"]
        raise "launch failed"
      end
      env = { machine: machine }
      action = VagrantPlugins::QEMU::Action::ResetVirtioFSArgs.new(app, env)
      expect { action.call(env) }.to raise_error("launch failed")
      env[:virtiofs_logs_shown] = true if shown
      action.recover(env)
      if shown
        expect(ui).not_to have_received(:error).with(/virtiofsd log/)
      else
        expect(ui).to have_received(:error).with(/virtiofsd log .*\ndiagnostic/m)
      end
    end
  end

  it "recognizes and terminates a real owned daemon process", :unix_only do
    skip "VirtioFS daemons run in Linux, not native Windows" if Vagrant::Util::Platform.windows?
    allow(Process).to receive(:kill).and_call_original
    allow(Open3).to receive(:capture2e).and_call_original
    config.virtiofsd_bin = RbConfig.ruby
    socket = @dir.join("owned.sock").to_s
    pid = Process.spawn(RbConfig.ruby, "-e", "sleep 30", "--", "--socket-path=#{socket}")
    FileUtils.mkdir_p(@dir.join("virtiofs"))
    File.write(@dir.join("virtiofs/virtiofs0.pid"), pid.to_s)
    File.write(@dir.join("virtiofs/virtiofs0.sock_path"), socket)
    identity = adapter.send(:process_identity, pid)
    expect(identity).to include("--socket-path=#{socket}")
    File.write(@dir.join("virtiofs/virtiofs0.process.json"), JSON.generate("identity" => identity, "binary" => RbConfig.ruby))
    adapter.cleanup(machine, {})
    Process.wait(pid)
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
  ensure
    if pid
      Process.kill("TERM", pid) rescue Errno::ESRCH
      Process.wait(pid) rescue Errno::ECHILD
    end
  end

  it "lets Warden stop QEMU before cleaning VirtioFS and preserves the boot error" do
    allow(driver).to receive(:running?).and_return(true)
    start = Class.new do
      def initialize(app, env)
        @app = app
      end

      def call(env)
        env[:machine].provider_config.virtiofs_qemu_args = ["-device", "vhost-user-fs-pci"]
        dir = env[:machine].data_dir.join("virtiofs")
        FileUtils.mkdir_p(dir)
        File.write(dir.join("mounts.json"), '{}')
        File.write(dir.join("virtiofs0.log"), 'boot diagnostic')
        @app.call(env)
      end

      def recover(env)
        env[:machine].provider.driver.stop
      end
    end
    expect(driver).to receive(:stop) { allow(driver).to receive(:running?).and_return(false) }
    error = Vagrant::Errors::VMBootTimeout.new
    env = { machine: machine, ui: ui }
    warden = Vagrant::Action::Warden.new([
      VagrantPlugins::QEMU::Action::ResetVirtioFSArgs, start, ->(_) { raise error }
    ], env)
    expect { warden.call(env) }.to raise_error(error)
    expect(env["vagrant.error"]).to equal(error)
    expect(@dir.join("virtiofs/mounts.json")).not_to exist
    expect(File.read(@dir.join("virtiofs/virtiofs0.log"))).to eq('boot diagnostic')
    expect(config.virtiofs_qemu_args).to be_empty
  end
end
