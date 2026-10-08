require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "runtime observer and COM1 log" do
  around do |example|
    with_temp_dir do |dir|
      @dir = dir
      @driver = described_class.new("vq_observer", dir.join("data"), dir.join("tmp"))
      FileUtils.mkdir_p(dir.join("data", "vq_observer"))
      example.run
    end
  end

  def options
    config = VagrantPlugins::QEMU::Config.new
    config.arch = "x86_64"
    config.finalize!
    config.instance_variables.to_h { |key| [key.to_s.delete_prefix("@").to_sym, config.instance_variable_get(key)] }.merge(ports: [], serial_log_file: @dir.join("logs", "sac.log").to_s)
  end

  it "records actual launched argv, live PID and owned COM1 logging without duplicating serial" do
    allow(Vagrant::Util::Which).to receive(:which).and_return("qemu")
    allow(@driver).to receive(:running?).and_return(false, true)
    launched = nil
    allow(@driver).to receive(:execute) do |*argv, **_|
      launched = argv
      File.write(@driver.tmp_dir.join("vq_observer", "qemu.pid"), "12345")
      ""
    end
    @driver.start(options)
    path = @driver.tmp_dir.join("vq_observer", "runtime.json")
    record = JSON.parse(File.read(path))
    expect(record.fetch("argv")).to eq(launched)
    expect(record.fetch("pid")).to eq(12345)
    expect(record.fetch("vm_id")).to eq("vq_observer")
    expect(record.fetch("serial").fetch("slot")).to eq(1)
    expect(record.fetch("serial_log_file")).to eq(options.fetch(:serial_log_file))
    expect(launched.count("-serial")).to eq(1)
    expect(launched.grep(/id=ser0/).first).to end_with("logfile=#{options.fetch(:serial_log_file)},logappend=on")
    allow(@driver).to receive(:running?).and_return(false)
    @driver.stop(graceful_timeout: 0)
    expect(path).to exist
    @driver.delete
    expect(path).not_to exist
  end

  it "never records a failed launch as observed runtime" do
    allow(Vagrant::Util::Which).to receive(:which).and_return("qemu")
    allow(@driver).to receive(:running?).and_return(false)
    allow(@driver).to receive(:execute).and_raise(IOError, "launch failed")
    expect { @driver.start(options) }.to raise_error(IOError, "launch failed")
    expect(@driver.tmp_dir.join("vq_observer", "runtime.json")).not_to exist
  end
end
