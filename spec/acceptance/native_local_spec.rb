require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "native local lifecycle", :requires_native_qemu do
  it "boots native pflash, halts through AF_UNIX, reloads and force halts without an orphan" do
    with_temp_dir do |dir|
      config = VagrantPlugins::QEMU::Config.new
      config.arch = "x86_64"
      config.finalize!
      opts = config.instance_variables.to_h { |key| [key.to_s.delete_prefix("@").to_sym, config.instance_variable_get(key)] }.merge(
        qemu_bin: ENV.fetch("QEMU_BINARY", "C:/Program Files/qemu/qemu-system-x86_64.exe"),
        machine: Vagrant::Util::Platform.windows? ? "q35,accel=whpx,kernel-irqchip=off" : "q35,accel=kvm", cpu: Vagrant::Util::Platform.windows? ? "max" : "host", memory: "512M", smp: "1",
        firmware: ENV.fetch("QEMU_FIRMWARE", "C:/Program Files/qemu/share/edk2-x86_64-code.fd"),
        efi_vars: ENV.fetch("QEMU_EFI_VARS", "C:/Program Files/qemu/share/edk2-i386-vars.fd"),
        image_path: [], ports: [], net_device: nil, drive_interface: nil)
      importer = described_class.new(nil, dir.join("data"), dir.join("tmp"))
      id = importer.import(opts).fetch(:id)
      driver = described_class.new(id, dir.join("data"), dir.join("tmp"))
      allow(driver.instance_variable_get(:@logger)).to receive(:debug) { |message| puts message }
      begin
        allow(driver).to receive(:execute).and_wrap_original do |original, *cmd, **kwargs|
          puts "Provider argv=#{cmd.to_json}"
          original.call(*cmd, **kwargs)
        end
        driver.start(opts)
        expect(driver.running?).to eq(true)
        serial_path = Vagrant::Util::Platform.windows? ? driver.send(:local_socket, 'serial') : driver.tmp_dir.join(id, "qemu_socket_serial").to_s
        2.times { Socket.unix(serial_path) { |socket| expect(socket).not_to be_closed } }
        first_pid = driver.send(:process_id)
        puts "Native pflash launch PID=#{first_pid}"
        expect(driver).not_to receive(:force_kill)
        driver.stop(graceful_timeout: 1)
        expect(driver.running?).to eq(false)
        puts "Local AF_UNIX halt confirmed PID=#{first_pid} gone"
        vars = dir.join("data", id, "efi-vars.fd")
        RSpec::Mocks.space.proxy_for(driver).reset
        digest = Digest::SHA256.file(vars).hexdigest
        driver.start(opts)
        expect(driver.running?).to eq(true)
        expect(Digest::SHA256.file(vars).hexdigest).to eq(digest)
        second_pid = driver.send(:process_id)
        # Inject the unavailable-monitor condition to exercise actual host KILL.
        allow(driver).to receive(:send_monitor).and_return(nil)
        driver.stop(graceful_timeout: 0)
        expect(driver.running?).to eq(false)
        if Vagrant::Util::Platform.windows?
          expect(driver.send(:windows_running?, second_pid)).to eq(false)
        else
          expect { Process.kill(0, second_pid) }.to raise_error(Errno::ESRCH)
        end
        puts "Forced halt confirmed PID=#{second_pid} gone; NVRAM retained across reload"
        driver.delete
        expect(dir.join("data", id)).not_to exist
      ensure
        RSpec::Mocks.space.proxy_for(driver).reset
        driver.send(:force_kill) if driver.running?
      end
    end
  end
end
