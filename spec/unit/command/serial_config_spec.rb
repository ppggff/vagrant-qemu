require "spec_helper"
require "json"

command_file = File.expand_path("../../../lib/vagrant-qemu/command/serial_config.rb", __dir__)
require command_file if File.file?(command_file)

describe "serial-config command" do
  let(:ui) { double("ui", output: nil) }
  let(:env) { double("environment", ui: ui) }
  let(:unix_endpoint) { { type: :unix, path: "/tmp/with spaces/qemu_socket_serial" } }

  def machine(name, endpoint, id = "vm-id")
    driver = double("driver", serial_endpoint: endpoint)
    double("machine", name: name, id: id, provider_name: :qemu,
      provider: double("provider", driver: driver), provider_config: double("config", debug_port: nil))
  end

  def command(argv, machines)
    cmd = VagrantPlugins::QEMU::Command::SerialConfig.new(argv, env)
    allow(cmd).to receive(:with_target_vms) do |*args, &block|
      machines.each { |vm| block.call(vm) }
    end
    cmd
  end

  it "maps every selected machine to its Unix or TCP endpoint" do
    cmd = command([], [machine(:first, unix_endpoint), machine(:second, { type: :tcp, host: "127.0.0.1", port: 33334 })])
    expect(cmd.execute).to eq 0
    expect(ui).to have_received(:output).with(include("first", "/tmp/with spaces/qemu_socket_serial"))
    expect(ui).to have_received(:output).with(include("second", "127.0.0.1", "33334"))
  end

  it "passes the requested machine selector to Vagrant's QEMU target resolution" do
    cmd = command(["second"], [machine(:second, unix_endpoint)])
    cmd.execute
    expect(cmd).to have_received(:with_target_vms).with(["second"], provider: :qemu)
  end

  it "provides JSON without losing spaces in socket paths" do
    cmd = command(["--json"], [machine(:first, unix_endpoint)])
    expect(cmd.execute).to eq 0
    expect(ui).to have_received(:output) do |output|
      expect(JSON.parse(output)).to eq [{ "machine" => "first", "endpoint" => { "type" => "unix", "path" => "/tmp/with spaces/qemu_socket_serial" } }]
    end
  end

  it "reports uncreated machines without booting or requesting a driver" do
    vm = machine(:fresh, nil, nil)
    cmd = command(["--json"], [vm])
    expect(cmd.execute).to eq 0
    expect(vm).not_to have_received(:provider)
    expect(ui).to have_received(:output) do |output|
      expect(JSON.parse(output)).to eq [{ "machine" => "fresh", "endpoint" => nil }]
    end
  end

  it "prints help without resolving machines" do
    cmd = command(["--help"], [])
    allow(cmd).to receive(:safe_puts)
    cmd.execute
    expect(cmd).not_to have_received(:with_target_vms)
    expect(cmd).to have_received(:safe_puts).with(include("serial-config"))
  end
end
