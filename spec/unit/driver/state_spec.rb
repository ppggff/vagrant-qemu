require "spec_helper"

describe VagrantPlugins::QEMU::Driver do
  let(:vm_id) { "vq_testid123" }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      @tmp_base = dir.join("tmp")
      FileUtils.mkdir_p(@data_dir)
      FileUtils.mkdir_p(@tmp_base)
      example.run
    end
  end

  subject { described_class.new(vm_id, @data_dir, @tmp_base) }

  describe "#get_current_state" do
    it "returns :not_created when directory does not exist" do
      expect(subject.get_current_state).to eq :not_created
    end

    it "returns :stopped when directory exists but no PID file" do
      FileUtils.mkdir_p(@data_dir.join(vm_id))
      expect(subject.get_current_state).to eq :stopped
    end

    it "returns :running when directory exists and process alive" do
      FileUtils.mkdir_p(@data_dir.join(vm_id))
      pid = spawn_fake_qemu(@data_dir.join(vm_id, "run", "qemu.pid"))
      expect(subject.get_current_state).to eq :running
    ensure
      kill_fake_qemu(pid) if pid
    end
  end

  describe "#running?" do
    it "returns false when PID file does not exist" do
      expect(subject.running?).to eq false
    end

    it "returns false when PID file exists but process is dead" do
      pid_dir = @tmp_base.join("vagrant-qemu", vm_id)
      FileUtils.mkdir_p(pid_dir)
      File.write(pid_dir.join("qemu.pid"), "999999999")
      expect(subject.running?).to eq false
    end

    it "returns false when the PID file is still empty" do
      pid_dir = @tmp_base.join("vagrant-qemu", vm_id)
      FileUtils.mkdir_p(pid_dir)
      File.write(pid_dir.join("qemu.pid"), "")
      expect(subject.running?).to eq false
    end

    it "returns false when QEMU removes the PID file while it is being read" do
      pid_dir = @tmp_base.join("vagrant-qemu", vm_id)
      FileUtils.mkdir_p(pid_dir)
      pid_file = pid_dir.join("qemu.pid")
      File.write(pid_file, Process.pid.to_s)
      allow(File).to receive(:read).and_wrap_original do |original, path, *args|
        File.delete(pid_file) if path.to_s == pid_file.to_s && File.exist?(pid_file)
        original.call(path, *args)
      end

      expect(subject.running?).to eq false
    end
  end

  describe "#running? across runtime layouts" do
    let(:run_pid_file) { @data_dir.join(vm_id, "run", "qemu.pid") }
    let(:legacy_pid_file) { @tmp_base.join("vagrant-qemu", vm_id, "qemu.pid") }

    after { @fake.each { |pid| kill_fake_qemu(pid) } if @fake }

    def fake(path)
      (@fake ||= []) << spawn_fake_qemu(path)
      @fake.last
    end

    it "finds a VM started under the project-local layout" do
      fake(run_pid_file)
      expect(subject.running?).to eq true
    end

    it "still finds it after the tmp runtime directory is removed" do
      fake(run_pid_file)
      FileUtils.rm_rf(@tmp_base.join("vagrant-qemu"))
      expect(subject.running?).to eq true
    end

    it "finds a VM that an older version started under the tmp layout" do
      fake(legacy_pid_file)
      expect(subject.running?).to eq true
    end

    it "ignores a pidfile whose PID now belongs to an unrelated process" do
      FileUtils.mkdir_p(run_pid_file.dirname)
      File.write(run_pid_file, Process.pid.to_s)
      expect(subject.running?).to eq false
    end

    it "ignores a pidfile left in the VM directory by 0.3.6 and earlier" do
      FileUtils.mkdir_p(@data_dir.join(vm_id))
      File.write(@data_dir.join(vm_id, "qemu.pid"), Process.pid.to_s)
      expect(subject.running?).to eq false
    end

    it "reports another user's unrelated process as not running instead of raising" do
      FileUtils.mkdir_p(run_pid_file.dirname)
      File.write(run_pid_file, "1")
      expect { subject.running? }.not_to raise_error
      expect(subject.running?).to eq false
    end

    it "reports a VM owned by another user as running" do
      pid = fake(run_pid_file)
      allow(Process).to receive(:kill).and_call_original
      allow(Process).to receive(:kill).with(0, pid).and_raise(Errno::EPERM)
      expect(subject.running?).to eq true
    end

    it "falls back to the kill(0) answer when ps is unavailable" do
      FileUtils.mkdir_p(run_pid_file.dirname)
      File.write(run_pid_file, Process.pid.to_s)
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)
      expect(subject.running?).to eq true
    end

    context "when the project path is not ASCII" do
      subject { described_class.new(vm_id, @data_dir.join("项目 a"), @tmp_base) }

      it "matches the VM in ps output under the C locale" do
        fake(@data_dir.join("项目 a", vm_id, "run", "qemu.pid"))
        saved = ENV["LC_ALL"]
        ENV["LC_ALL"] = "C"
        expect(subject.running?).to eq true
      ensure
        ENV["LC_ALL"] = saved
      end
    end

    it "keeps finding the VM after the project directory is moved" do
      fake(run_pid_file)
      moved = @data_dir.dirname.join("moved")
      FileUtils.mv(@data_dir, moved)
      driver = described_class.new(vm_id, moved, @tmp_base)
      expect(driver.running?).to eq true
    end
  end

  describe "#created?" do
    it "returns true when data directory exists" do
      FileUtils.mkdir_p(@data_dir.join(vm_id))
      expect(subject.created?).to eq true
    end

    it "returns false when data directory does not exist" do
      expect(subject.created?).to eq false
    end
  end
end
