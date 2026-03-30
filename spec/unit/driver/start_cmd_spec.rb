require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "start command line (single NIC)" do
  let(:vm_id) { "vq_testid123" }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      @tmp_base = dir.join("tmp")
      FileUtils.mkdir_p(@data_dir)
      FileUtils.mkdir_p(@tmp_base)

      # Create VM directory with a dummy image
      id_dir = @data_dir.join(vm_id)
      FileUtils.mkdir_p(id_dir)
      FileUtils.touch(id_dir.join("linked-box.img"))

      # Create firmware files for aarch64 tests
      FileUtils.touch(id_dir.join("edk2-aarch64-code.fd"))
      FileUtils.touch(id_dir.join("edk2-arm-vars.fd"))

      example.run
    end
  end

  subject { described_class.new(vm_id, @data_dir, @tmp_base) }

  let(:base_options) do
    {
      ssh_host: "127.0.0.1", ssh_port: 50022,
      arch: "aarch64", machine: "virt,accel=hvf,highmem=on",
      cpu: "host", smp: "2", memory: "4G",
      net_device: "virtio-net-device", drive_interface: "virtio",
      qemu_bin: nil, extra_qemu_args: [], extra_netdev_args: nil,
      extra_drive_args: nil, ports: [], control_port: nil,
      debug_port: nil, no_daemonize: false, firmware_format: "raw",
      other_default: %w(-parallel null -monitor none -display none -vga none),
      extra_image_opts: nil, advanced_network: false,
      net_mode: :auto, private_networks: [],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
    }
  end

  # Capture the command passed to execute
  before do
    @captured_cmd = nil
    allow(subject).to receive(:execute) do |*cmd, **opts|
      @captured_cmd = cmd
      ""
    end
    allow(subject).to receive(:running?).and_return(false)
    # Stub qemu binary check
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu-system-aarch64")
  end

  it "includes basic -machine, -cpu, -smp, -m" do
    subject.start(base_options)
    expect(@captured_cmd).to include("-machine", "virt,accel=hvf,highmem=on")
    expect(@captured_cmd).to include("-cpu", "host")
    expect(@captured_cmd).to include("-smp", "2")
    expect(@captured_cmd).to include("-m", "4G")
  end

  it "includes -device and -netdev user for single NIC" do
    subject.start(base_options)
    expect(@captured_cmd.join(" ")).to include("-device virtio-net-device,netdev=net0")
    expect(@captured_cmd.join(" ")).to include("-netdev user,id=net0,hostfwd=tcp::50022-:22")
  end

  it "includes SSH hostfwd" do
    subject.start(base_options)
    expect(@captured_cmd.join(" ")).to match(/hostfwd=tcp::50022-:22/)
  end

  it "includes extra forwarded ports" do
    opts = base_options.merge(ports: ["tcp::8080-:80"])
    subject.start(opts)
    expect(@captured_cmd.join(" ")).to match(/hostfwd=tcp::8080-:80/)
  end

  it "includes drive arguments" do
    subject.start(base_options)
    expect(@captured_cmd.join(" ")).to match(/-drive if=virtio,id=disk0,format=qcow2/)
  end

  it "includes aarch64 firmware pflash" do
    subject.start(base_options)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).to match(/-drive if=pflash,format=raw.*edk2-aarch64-code\.fd.*readonly=on/)
    expect(cmd_str).to match(/-drive if=pflash,format=raw.*edk2-arm-vars\.fd/)
  end

  it "skips -machine when machine=nil" do
    opts = base_options.merge(machine: nil)
    subject.start(opts)
    expect(@captured_cmd).not_to include("-machine")
  end

  it "skips -cpu when cpu=nil" do
    opts = base_options.merge(cpu: nil)
    subject.start(opts)
    expect(@captured_cmd).not_to include("-cpu")
  end

  it "skips all network when net_device=nil" do
    opts = base_options.merge(net_device: nil)
    subject.start(opts)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).not_to include("-netdev")
    expect(cmd_str).not_to include("netdev=net0")
  end

  it "appends extra_qemu_args" do
    opts = base_options.merge(extra_qemu_args: %w(-accel tcg,thread=multi))
    subject.start(opts)
    expect(@captured_cmd).to include("-accel", "tcg,thread=multi")
  end

  it "appends extra_netdev_args" do
    opts = base_options.merge(extra_netdev_args: "net=192.168.51.0/24")
    subject.start(opts)
    expect(@captured_cmd.join(" ")).to include(",net=192.168.51.0/24")
  end

  it "appends extra_drive_args" do
    opts = base_options.merge(extra_drive_args: "cache=none,aio=threads")
    subject.start(opts)
    expect(@captured_cmd.join(" ")).to include(",cache=none,aio=threads")
  end

  it "raises QemuBinaryNotFound when binary missing" do
    allow(Vagrant::Util::Which).to receive(:which).and_return(nil)
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with("qemu-system-aarch64").and_return(false)

    expect { subject.start(base_options) }.to raise_error(
      VagrantPlugins::QEMU::Errors::QemuBinaryNotFound
    )
  end

  it "uses custom qemu_bin path" do
    opts = base_options.merge(qemu_bin: "/custom/qemu")
    allow(Vagrant::Util::Which).to receive(:which).and_return(nil)
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with("/custom/qemu").and_return(true)

    subject.start(opts)
    expect(@captured_cmd.first).to eq "/custom/qemu"
  end

  it "handles qemu_bin as array" do
    opts = base_options.merge(qemu_bin: ["/custom/qemu", "--special"])
    allow(Vagrant::Util::Which).to receive(:which).and_return(nil)
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with("/custom/qemu").and_return(true)

    subject.start(opts)
    expect(@captured_cmd[0]).to eq "/custom/qemu"
    expect(@captured_cmd[1]).to eq "--special"
  end
end
