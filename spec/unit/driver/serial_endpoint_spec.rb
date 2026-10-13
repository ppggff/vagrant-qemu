require "spec_helper"

describe "serial endpoint discovery" do
  around do |example|
    with_temp_dir do |dir|
      @driver = VagrantPlugins::QEMU::Driver.new("vm", dir.join("data"), dir.join("tmp"))
      @runtime_dir = @driver.tmp_dir.join("vm")
      FileUtils.mkdir_p(@runtime_dir)
      example.run
    end
  end

  it "returns the machine's actual runtime socket directory" do
    expect(@driver.serial_endpoint(nil)).to eq(type: :unix, path: @runtime_dir.join("qemu_socket_serial").to_s)
  end

  it "uses configured TCP serial for older runtime files" do
    File.write(@runtime_dir.join("options.yml"), { control_port: 33333 }.to_yaml)
    expect(@driver.serial_endpoint(33334)).to eq(type: :tcp, host: "127.0.0.1", port: 33334)
  end

  it "uses the running instance's TCP port after configuration changes" do
    File.write(@runtime_dir.join("options.yml"), { debug_port: 33334 }.to_yaml)
    expect(@driver.serial_endpoint(44444)).to eq(type: :tcp, host: "127.0.0.1", port: 33334)
  end

  it "keeps the running instance's Unix endpoint after a TCP configuration change" do
    File.write(@runtime_dir.join("options.yml"), { debug_port: nil }.to_yaml)
    expect(@driver.serial_endpoint(44444)).to eq(type: :unix, path: @runtime_dir.join("qemu_socket_serial").to_s)
  end

  it "does not invent an endpoint for an uncreated machine" do
    driver = VagrantPlugins::QEMU::Driver.new(nil, @driver.data_dir, @driver.tmp_dir)
    expect(driver.serial_endpoint(33334)).to be_nil
  end
end
