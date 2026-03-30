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
      pid_dir = @tmp_base.join("vagrant-qemu", vm_id)
      FileUtils.mkdir_p(pid_dir)
      File.write(pid_dir.join("qemu.pid"), Process.pid.to_s)
      expect(subject.get_current_state).to eq :running
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
