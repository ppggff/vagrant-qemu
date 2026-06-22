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
    allow(subject).to receive(:running?).and_return(false)
    expect(subject).not_to receive(:send_monitor)
    subject.stop(control_port: nil)
  end

  it "sends system_powerdown first and stops there when the guest powers off" do
    # running on the initial check, stopped on the first poll
    allow(subject).to receive(:running?).and_return(true, false)
    allow(subject).to receive(:send_monitor)

    subject.stop(control_port: nil, graceful_timeout: 5)

    expect(subject).to have_received(:send_monitor).with(anything, "system_powerdown")
    expect(subject).not_to have_received(:send_monitor).with(anything, "quit")
  end

  it "escalates to 'quit' when powerdown does not stop the VM" do
    allow(subject).to receive(:sleep)
    # stays up through the powerdown wait, then stops during the quit wait
    allow(subject).to receive(:running?).and_return(true, true, true, false)
    allow(subject).to receive(:send_monitor)
    expect(subject).not_to receive(:force_kill)

    subject.stop(control_port: nil, graceful_timeout: 1)

    expect(subject).to have_received(:send_monitor).with(anything, "system_powerdown").ordered
    expect(subject).to have_received(:send_monitor).with(anything, "quit").ordered
  end

  it "force kills only after both powerdown and 'quit' fail" do
    allow(subject).to receive(:sleep)
    allow(subject).to receive(:running?).and_return(true) # never stops
    allow(subject).to receive(:send_monitor)

    pid_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(pid_dir)
    File.write(pid_dir.join("qemu.pid"), "999999999")
    allow(Process).to receive(:kill).with("KILL", 999999999).and_raise(Errno::ESRCH)

    subject.stop(control_port: nil, graceful_timeout: 1)

    expect(subject).to have_received(:send_monitor).with(anything, "system_powerdown")
    expect(subject).to have_received(:send_monitor).with(anything, "quit")
    expect(Process).to have_received(:kill).with("KILL", 999999999)
  end

  it "prefers the persisted control_port over the configured one" do
    allow(subject).to receive(:running?).and_return(true, false)
    allow(subject).to receive(:send_monitor)

    opts_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(opts_dir)
    File.write(opts_dir.join("options.yml"), { ssh_port: 50022, control_port: 44444 }.to_yaml)

    subject.stop(control_port: 33333)

    expect(subject).to have_received(:send_monitor)
      .with(hash_including(control_port: 44444), "system_powerdown")
  end

  it "keeps the configured control_port when nothing is persisted" do
    allow(subject).to receive(:running?).and_return(true, false)
    allow(subject).to receive(:send_monitor)

    subject.stop(control_port: 33333)

    expect(subject).to have_received(:send_monitor)
      .with(hash_including(control_port: 33333), "system_powerdown")
  end

  it "swallows ESRCH on force_kill when the process is already gone" do
    allow(subject).to receive(:sleep)
    allow(subject).to receive(:running?).and_return(true)
    allow(subject).to receive(:send_monitor)

    pid_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(pid_dir)
    File.write(pid_dir.join("qemu.pid"), "999999999")
    allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

    expect { subject.stop(control_port: nil, graceful_timeout: 1) }.not_to raise_error
  end
end
