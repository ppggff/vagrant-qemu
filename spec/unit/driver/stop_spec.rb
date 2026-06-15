require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "#stop" do
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

  it "does nothing when not running" do
    expect(subject).not_to receive(:send_powerdown)
    subject.stop(control_port: nil)
  end

  it "sends powerdown when running" do
    allow(subject).to receive(:running?).and_return(true, false)
    allow(subject).to receive(:send_powerdown)

    subject.stop(control_port: nil)

    expect(subject).to have_received(:send_powerdown)
  end

  it "returns when VM shuts down within timeout" do
    call_count = 0
    allow(subject).to receive(:running?) do
      call_count += 1
      call_count <= 1 # running on first call, stopped on second
    end
    allow(subject).to receive(:send_powerdown)

    subject.stop(control_port: nil, graceful_timeout: 5)
  end

  it "force kills when VM does not shut down within timeout" do
    allow(subject).to receive(:running?).and_return(true)
    allow(subject).to receive(:send_powerdown)
    allow(subject).to receive(:sleep)

    pid_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(pid_dir)
    File.write(pid_dir.join("qemu.pid"), "999999999")

    allow(Process).to receive(:kill).with("KILL", 999999999).and_raise(Errno::ESRCH)

    expect { subject.stop(control_port: nil, graceful_timeout: 1) }.not_to raise_error
  end

  it "prefers the persisted control_port over the configured one" do
    allow(subject).to receive(:running?).and_return(true, false)
    allow(subject).to receive(:send_powerdown)

    opts_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(opts_dir)
    File.write(opts_dir.join("options.yml"), { ssh_port: 50022, control_port: 44444 }.to_yaml)

    subject.stop(control_port: 33333)

    expect(subject).to have_received(:send_powerdown)
      .with(hash_including(control_port: 44444))
  end

  it "keeps the configured control_port when nothing is persisted" do
    allow(subject).to receive(:running?).and_return(true, false)
    allow(subject).to receive(:send_powerdown)

    subject.stop(control_port: 33333)

    expect(subject).to have_received(:send_powerdown)
      .with(hash_including(control_port: 33333))
  end

  it "swallows ESRCH on force_kill when process already gone" do
    allow(subject).to receive(:running?).and_return(true)
    allow(subject).to receive(:send_powerdown)
    allow(subject).to receive(:sleep)

    pid_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(pid_dir)
    File.write(pid_dir.join("qemu.pid"), "999999999")

    allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

    expect { subject.stop(control_port: nil, graceful_timeout: 1) }.not_to raise_error
  end
end
