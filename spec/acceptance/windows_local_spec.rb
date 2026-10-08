require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "native Windows local lifecycle", :requires_windows_qemu do
  it "boots pflash on WHPX, halts through a local pipe, reloads and force halts without an orphan" do
    with_temp_dir do |dir|
      config = VagrantPlugins::QEMU::Config.new
      config.arch = "x86_64"
      config.finalize!
      opts = config.instance_variables.to_h { |key| [key.to_s.delete_prefix("@").to_sym, config.instance_variable_get(key)] }.merge(
        qemu_bin: "C:/Program Files/qemu/qemu-system-x86_64.exe",
        machine: "q35,accel=whpx,kernel-irqchip=off", cpu: "max", memory: "512M", smp: "1",
        firmware: "C:/Program Files/qemu/share/edk2-x86_64-code.fd",
        efi_vars: "C:/Program Files/qemu/share/edk2-i386-vars.fd",
        image_path: [], ports: [], net_device: nil, drive_interface: nil)
      importer = described_class.new(nil, dir.join("data"), dir.join("tmp"))
      id = importer.import(opts).fetch(:id)
      driver = described_class.new(id, dir.join("data"), dir.join("tmp"))
      begin
        driver.start(opts)
        expect(driver.running?).to eq(true)
        first_pid = driver.send(:process_id)
        puts "WHPX pflash launch PID=#{first_pid}; monitor=#{driver.send(:pipe_name, 'monitor')}"
        driver.stop(graceful_timeout: 0)
        expect(driver.running?).to eq(false)
        puts "Local-pipe halt confirmed PID=#{first_pid} gone"
        vars = dir.join("data", id, "efi-vars.fd")
        digest = Digest::SHA256.file(vars).hexdigest
        driver.start(opts)
        expect(driver.running?).to eq(true)
        expect(Digest::SHA256.file(vars).hexdigest).to eq(digest)
        second_pid = driver.send(:process_id)
        # Inject the unavailable-monitor condition to exercise actual Windows KILL.
        allow(driver).to receive(:send_monitor).and_return(nil)
        driver.stop(graceful_timeout: 0)
        expect(driver.running?).to eq(false)
        expect(driver.send(:windows_running?, second_pid)).to eq(false)
        puts "Forced halt confirmed PID=#{second_pid} gone; NVRAM retained across reload"
        driver.delete
        expect(dir.join("data", id)).not_to exist
      ensure
        driver.send(:force_kill) if driver.running?
      end
    end
  end
end
