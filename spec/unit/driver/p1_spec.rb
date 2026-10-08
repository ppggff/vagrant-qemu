require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "P1 local lifecycle" do
  around do |example|
    with_temp_dir do |dir|
      @dir = dir
      @driver = described_class.new("vq_p1", dir.join("data"), dir.join("tmp"))
      FileUtils.mkdir_p(dir.join("data", "vq_p1"))
      example.run
    end
  end

  def options
    config = VagrantPlugins::QEMU::Config.new
    config.arch = "x86_64"
    config.finalize!
    config.instance_variables.to_h { |key| [key.to_s.delete_prefix("@").to_sym, config.instance_variable_get(key)] }.merge(ports: [])
  end

  it "copies pristine x86 firmware once and preserves Machine vars across starts" do
    code = @dir.join("code.fd")
    vars = @dir.join("vars.fd")
    File.write(code, "code")
    File.write(vars, "pristine")
    allow(@driver).to receive(:execute).and_return("")
    imported = @driver.import(options.merge(firmware: code.to_s, efi_vars: vars.to_s, image_path: []))
    live_vars = @dir.join("data", imported[:id], "efi-vars.fd")
    expect(File.read(live_vars)).to eq("pristine")
    File.write(live_vars, "guest-written")
    driver = described_class.new(imported[:id], @dir.join("data"), @dir.join("tmp"))
    allow(Vagrant::Util::Which).to receive(:which).and_return("qemu")
    calls = []
    allow(driver).to receive(:execute) { |*cmd, **_| calls << cmd; "" }
    2.times { driver.start(options.merge(firmware: code.to_s, efi_vars: vars.to_s)) }
    expect(File.read(live_vars)).to eq("guest-written")
    expect(File.read(vars)).to eq("pristine")
    expect(calls.first).to include("if=pflash,format=raw,unit=0,file=#{@dir.join('data', imported[:id], 'firmware.fd')},readonly=on", "if=pflash,format=raw,unit=1,file=#{live_vars}")
  end

  it "uses named pipes and detached launch on Windows without daemonize or TCP" do
    allow(@driver).to receive(:windows?).and_return(true)
    allow(Vagrant::Util::Which).to receive(:which).and_return("qemu")
    cmd = nil
    expect(@driver).to receive(:execute) { |*args, **kwargs| cmd = args; expect(kwargs).to eq(detach: true); "" }
    @driver.start(options.merge(qemu_bin: "C:/Program Files/qemu/qemu-system-x86_64.exe"))
    expect(cmd.first).to eq("C:/Program Files/qemu/qemu-system-x86_64.exe")
    expect(cmd).not_to include("-daemonize")
    expect(cmd.grep(/^pipe,/).length).to eq(2)
    expect(cmd.join(" ")).not_to include("host=localhost")
    expect(cmd.join(" ")).to include("hostfwd=tcp:127.0.0.1:50022-:22")
  end

  it "rejects destroying a running Machine instead of orphaning it" do
    allow(@driver).to receive(:running?).and_return(true)
    expect { @driver.delete }.to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
    expect(@dir.join("data", "vq_p1")).to exist
  end

  it "refuses invalid PID files rather than signaling the process group" do
    pidfile = @dir.join("tmp", "vagrant-qemu", "vq_p1", "qemu.pid")
    FileUtils.mkdir_p(pidfile.dirname)
    File.write(pidfile, "garbage")
    expect(Process).not_to receive(:kill)
    expect(@driver.running?).to eq(false)
    @driver.send(:force_kill)
  end
end
