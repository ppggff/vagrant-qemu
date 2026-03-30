require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "command line argument order" do
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

  before do
    @captured_cmd = nil
    allow(subject).to receive(:execute) do |*cmd, **opts|
      @captured_cmd = cmd
      ""
    end
    allow(subject).to receive(:running?).and_return(false)
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu-system-aarch64")
  end

  it "disk id starts at disk0 in dual NIC mode" do
    opts = base_options.merge(
      advanced_network: true, net_mode: :vmnet_shared,
      private_networks: [{ ip: "192.168.105.10" }]
    )
    subject.start(opts)
    expect(@captured_cmd.join(" ")).to match(/id=disk0/)
  end

  it "network arguments appear before drive arguments" do
    subject.start(base_options)
    cmd_str = @captured_cmd.join(" ")
    net_pos = cmd_str.index("-netdev user")
    drive_pos = cmd_str.index("-drive if=virtio")
    expect(net_pos).to be < drive_pos
  end
end
