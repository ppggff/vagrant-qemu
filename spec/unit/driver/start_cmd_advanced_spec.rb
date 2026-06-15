require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "start command line (dual NIC)" do
  let(:vm_id) { "vq_testid123" }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      @tmp_base = dir.join("tmp")
      FileUtils.mkdir_p(@data_dir)
      FileUtils.mkdir_p(@tmp_base)

      id_dir = @data_dir.join(vm_id)
      FileUtils.mkdir_p(id_dir)
      FileUtils.touch(id_dir.join("linked-box.img"))
      FileUtils.touch(id_dir.join("edk2-aarch64-code.fd"))
      FileUtils.touch(id_dir.join("edk2-arm-vars.fd"))

      example.run
    end
  end

  subject { described_class.new(vm_id, @data_dir, @tmp_base) }

  let(:advanced_options) do
    {
      ssh_host: "127.0.0.1", ssh_port: 50022,
      arch: "aarch64", machine: "virt,accel=hvf,highmem=on",
      cpu: "host", smp: "2", memory: "4G",
      net_device: "virtio-net-device", drive_interface: "virtio",
      qemu_bin: nil, extra_qemu_args: [], extra_netdev_args: nil,
      extra_drive_args: nil, ports: [], control_port: nil,
      debug_port: nil, no_daemonize: false, firmware_format: "raw",
      other_default: %w(-parallel null -monitor none -display none -vga none),
      extra_image_opts: nil,
      advanced_network: true, net_mode: :vmnet_shared,
      private_networks: [{ ip: "192.168.105.10", netmask: "255.255.255.0" }],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
    }
  end

  before do
    @captured_cmd = nil
    allow(subject).to receive(:execute) do |*cmd, **opts|
      @captured_cmd = cmd
      ""
    end
    allow(subject).to receive(:running?).and_return(false)
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu-system-aarch64")
  end

  it "adds MAC address to NIC 0" do
    subject.start(advanced_options)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).to match(/-device virtio-net-device,netdev=net0,mac=52:54:00:[0-9a-f:]+/)
  end

  it "NIC 0 is still user-mode with hostfwd" do
    subject.start(advanced_options)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).to include("-netdev user,id=net0,hostfwd=tcp::50022-:22")
  end

  it "adds NIC 1 with vmnet-shared backend" do
    subject.start(advanced_options)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).to include("-netdev vmnet-shared,id=net1")
  end

  it "NIC 1 has different MAC than NIC 0" do
    subject.start(advanced_options)
    cmd_str = @captured_cmd.join(" ")
    macs = cmd_str.scan(/mac=(52:54:00:[0-9a-f:]+)/)
    expect(macs.length).to eq 2
    expect(macs[0]).not_to eq macs[1]
  end

  it "uses user-specified MAC for NIC 1 when provided" do
    opts = advanced_options.merge(
      private_networks: [{ ip: "192.168.105.10", netmask: "255.255.255.0", mac: "AA:BB:CC:DD:EE:FF" }]
    )
    subject.start(opts)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).to include("mac=AA:BB:CC:DD:EE:FF")
  end

  it "does not write network-config itself (seed built by CloudInitNetwork action)" do
    subject.start(advanced_options)
    config_file = @tmp_base.join("vagrant-qemu", vm_id, "network-config")
    expect(config_file).not_to exist
  end

  it "falls back to single NIC when advanced_network=true but no private_networks" do
    opts = advanced_options.merge(private_networks: [])
    subject.start(opts)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).not_to include("net1")
    expect(cmd_str).not_to include("vmnet")
    # Should have single NIC without MAC
    expect(cmd_str).to include("-device virtio-net-device,netdev=net0")
    expect(cmd_str).not_to match(/mac=/)
  end

  it "disk id starts at disk0 even with dual NIC" do
    subject.start(advanced_options)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).to match(/id=disk0/)
  end
end
