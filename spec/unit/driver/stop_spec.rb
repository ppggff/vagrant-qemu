require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "#stop" do
  let(:vm_id) { "vq_testid123" }
  # No process has this PID, so kill(0) reports it gone once stop returns.
  let(:pid) { 999999999 }
  let(:run_dir) { @data_dir.join(vm_id, "run") }
  let(:legacy_dir) { @tmp_base.join("vagrant-qemu", vm_id) }

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

  def live_in(dir, live_pid = pid)
    FileUtils.mkdir_p(dir)
    allow(subject).to receive(:live_instance).and_return([dir, live_pid])
  end

  it "does nothing when not running" do
    allow(subject).to receive(:live_instance).and_return(nil)
    expect(subject).not_to receive(:send_monitor)
    subject.stop(control_port: nil)
  end

  context "with a reachable monitor" do
    before do
      live_in(run_dir)
      allow(subject).to receive(:send_monitor).and_return(true)
    end

    it "quits directly and allows time to flush after a failed boot" do
      allow(subject).to receive(:running?).and_return(true, true, false)
      allow(subject).to receive(:sleep)
      expect(subject).not_to receive(:force_kill)

      subject.stop(control_port: nil, graceful_timeout: 10, quit_only: true)

      expect(subject).not_to have_received(:send_monitor).with(anything, "system_powerdown")
      expect(subject).to have_received(:send_monitor).with(anything, "quit")
      expect(subject).to have_received(:sleep).with(1).twice
    end

    it "sends system_powerdown first and stops there when the guest powers off" do
      allow(subject).to receive(:running?).and_return(false)

      subject.stop(control_port: nil, graceful_timeout: 5)

      expect(subject).to have_received(:send_monitor).with(anything, "system_powerdown")
      expect(subject).not_to have_received(:send_monitor).with(anything, "quit")
    end

    it "escalates to 'quit' when powerdown does not stop the VM" do
      allow(subject).to receive(:sleep)
      # stays up through the powerdown wait, then stops during the quit wait
      allow(subject).to receive(:running?).and_return(true, true, false)
      expect(subject).not_to receive(:force_kill)

      subject.stop(control_port: nil, graceful_timeout: 1)

      expect(subject).to have_received(:send_monitor).with(anything, "system_powerdown").ordered
      expect(subject).to have_received(:send_monitor).with(anything, "quit").ordered
    end

    it "force kills only after both powerdown and 'quit' fail" do
      allow(subject).to receive(:sleep)
      allow(subject).to receive(:running?).and_return(true) # never stops
      allow(Process).to receive(:kill).and_call_original
      allow(Process).to receive(:kill).with("KILL", pid).and_raise(Errno::ESRCH)

      subject.stop(control_port: nil, graceful_timeout: 1)

      expect(subject).to have_received(:send_monitor).with(anything, "system_powerdown")
      expect(subject).to have_received(:send_monitor).with(anything, "quit")
      expect(Process).to have_received(:kill).with("KILL", pid)
      expect(Process).not_to have_received(:kill).with("TERM", anything)
    end

    it "prefers the persisted control_port over the configured one" do
      allow(subject).to receive(:running?).and_return(false)
      File.write(run_dir.join("options.yml"), { ssh_port: 50022, control_port: 44444 }.to_yaml)

      subject.stop(control_port: 33333)

      expect(subject).to have_received(:send_monitor)
        .with(hash_including(control_port: 44444), "system_powerdown")
    end

    it "keeps the configured control_port when nothing is persisted" do
      allow(subject).to receive(:running?).and_return(false)

      subject.stop(control_port: 33333)

      expect(subject).to have_received(:send_monitor)
        .with(hash_including(control_port: 33333), "system_powerdown")
    end

    it "connects to the monitor socket recorded at launch" do
      allow(subject).to receive(:running?).and_return(false)
      File.write(run_dir.join("options.yml"), { control_port: nil, monitor_socket: "/launch/qemu_socket" }.to_yaml)

      subject.stop(control_port: nil)

      expect(subject).to have_received(:send_monitor)
        .with(hash_including(monitor_socket: "/launch/qemu_socket"), "system_powerdown")
    end
  end

  context "when the monitor is unreachable" do
    before do
      live_in(run_dir)
      allow(subject).to receive(:send_monitor).and_return(false)
      allow(subject).to receive(:sleep)
      allow(Process).to receive(:kill).and_call_original
    end

    it "sends SIGTERM without waiting out graceful_timeout" do
      allow(Process).to receive(:kill).with("TERM", pid)
      allow(subject).to receive(:running?).and_return(true, false)

      subject.stop(control_port: nil, graceful_timeout: 60)

      expect(subject).not_to have_received(:send_monitor).with(anything, "quit")
      expect(Process).to have_received(:kill).with("TERM", pid)
      expect(Process).not_to have_received(:kill).with("KILL", anything)
      expect(subject).to have_received(:sleep).with(1).once
    end

    it "falls back to SIGKILL when SIGTERM does not stop QEMU within ten seconds" do
      allow(Process).to receive(:kill).with("TERM", pid)
      allow(Process).to receive(:kill).with("KILL", pid)
      allow(subject).to receive(:running?).and_return(true)

      subject.stop(control_port: nil, graceful_timeout: 60)

      expect(Process).to have_received(:kill).with("TERM", pid).ordered
      expect(Process).to have_received(:kill).with("KILL", pid).ordered
      expect(subject).to have_received(:sleep).with(1).exactly(10).times
    end

    it "goes straight to SIGKILL where SIGTERM is not supported" do
      allow(Process).to receive(:kill).with("TERM", pid).and_raise(ArgumentError)
      allow(Process).to receive(:kill).with("KILL", pid)
      allow(subject).to receive(:running?).and_return(false)

      subject.stop(control_port: nil, graceful_timeout: 60)

      expect(Process).to have_received(:kill).with("KILL", pid)
    end

    it "explains a VM started by another user instead of failing silently" do
      allow(Process).to receive(:kill).with("TERM", pid).and_raise(Errno::EPERM)
      allow(subject).to receive(:running?).and_return(true)

      expect { subject.stop(control_port: nil) }
        .to raise_error(VagrantPlugins::QEMU::Errors::QemuProcessNotOwned)
    end
  end

  describe "runtime files left after the process exits" do
    before do
      allow(subject).to receive(:sleep)
      allow(subject).to receive(:send_monitor).and_return(false)
      allow(Process).to receive(:kill).and_call_original
      allow(Process).to receive(:kill).with("TERM", anything)
      allow(Process).to receive(:kill).with("KILL", anything)
    end

    it "removes the pidfile and recorded sockets after SIGKILL" do
      live_in(run_dir)
      allow(subject).to receive(:running?).and_return(true)
      FileUtils.mkdir_p(legacy_dir)
      sockets = [legacy_dir.join("qemu_socket"), legacy_dir.join("qemu_socket_serial")]
      File.write(run_dir.join("options.yml"),
                 { monitor_socket: sockets[0].to_s, serial_socket: sockets[1].to_s }.to_yaml)
      ([run_dir.join("qemu.pid")] + sockets).each { |f| FileUtils.touch(f) }

      subject.stop(control_port: nil)

      ([run_dir.join("qemu.pid")] + sockets).each { |f| expect(f).not_to exist }
      expect(run_dir.join("options.yml")).to exist
    end

    it "removes an older version's runtime files once its VM is stopped" do
      live_in(legacy_dir)
      allow(subject).to receive(:running?).and_return(false)
      %w(qemu.pid options.yml qemu_socket qemu_socket_serial).each { |f| FileUtils.touch(legacy_dir.join(f)) }

      subject.stop(control_port: nil)

      expect(legacy_dir.children).to be_empty
    end

    it "keeps them while the PID still exists" do
      live_in(run_dir, Process.pid)
      allow(subject).to receive(:running?).and_return(true)
      FileUtils.touch(run_dir.join("qemu.pid"))

      subject.stop(control_port: nil)

      expect(run_dir.join("qemu.pid")).to exist
    end
  end

  context "after force_kill sends SIGKILL" do
    before do
      allow(Process).to receive(:kill).with("KILL", pid)
      allow(subject).to receive(:sleep)
    end

    it "waits until the process has exited" do
      allow(subject).to receive(:running?).and_return(true, true, false)
      subject.send(:force_kill, pid)
      expect(subject).to have_received(:running?).exactly(3).times
      expect(subject).to have_received(:sleep).with(0.1).twice
    end

    it "returns from stop only after the killed process has exited" do
      live_in(run_dir)
      allow(subject).to receive(:send_monitor).and_return(true)
      allow(Process).to receive(:kill).with(0, pid).and_raise(Errno::ESRCH)
      # quit wait (1 poll + final), then two polls after the kill
      allow(subject).to receive(:running?).and_return(true, true, true, false)
      subject.stop(control_port: nil, graceful_timeout: 1, quit_only: true)
      expect(Process).to have_received(:kill).with("KILL", pid)
      expect(subject).to have_received(:running?).exactly(4).times
    end

    it "gives up waiting after about two seconds" do
      allow(subject).to receive(:running?).and_return(true)
      subject.send(:force_kill, pid)
      expect(subject).to have_received(:sleep).with(0.1).exactly(20).times
    end
  end

  context "when the pidfile does not identify a live QEMU of this VM" do
    before do
      allow(subject).to receive(:sleep)
      allow(subject).to receive(:send_monitor)
      @pid_file = run_dir.join("qemu.pid")
      FileUtils.mkdir_p(run_dir)
    end

    it "does nothing when QEMU removes the file before it is read" do
      File.write(@pid_file, Process.pid.to_s)
      pid_file = @pid_file
      allow(File).to receive(:read).and_wrap_original do |original, path, *args|
        File.delete(pid_file) if path.to_s == pid_file.to_s && File.exist?(pid_file)
        original.call(path, *args)
      end
      expect(Process).not_to receive(:kill)

      expect { subject.stop(control_port: nil, graceful_timeout: 1) }.not_to raise_error
    end

    it "never signals a PID read from an empty file" do
      File.write(@pid_file, "")
      expect(Process).not_to receive(:kill)

      expect { subject.stop(control_port: nil, graceful_timeout: 1) }.not_to raise_error
    end

    it "never signals a reused PID that belongs to another process" do
      File.write(@pid_file, Process.pid.to_s)
      allow(Process).to receive(:kill).and_call_original

      subject.stop(control_port: nil, graceful_timeout: 1)

      expect(subject).not_to have_received(:send_monitor)
      expect(Process).not_to have_received(:kill).with("TERM", anything)
      expect(Process).not_to have_received(:kill).with("KILL", anything)
    end
  end
end
