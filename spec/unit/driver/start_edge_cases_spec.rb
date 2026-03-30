require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "start edge cases" do
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

      example.run
    end
  end

  subject { described_class.new(vm_id, @data_dir, @tmp_base) }

  before do
    @captured_cmd = nil
    allow(subject).to receive(:execute) do |*cmd, **opts|
      @captured_cmd = cmd
      ""
    end
    allow(subject).to receive(:running?).and_return(false)
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu-system-aarch64")
  end

  let(:base_options) do
    {
      ssh_host: "127.0.0.1", ssh_port: 50022,
      arch: "aarch64", machine: nil, cpu: nil, smp: nil, memory: nil,
      net_device: nil, drive_interface: nil,
      qemu_bin: nil, extra_qemu_args: [], extra_netdev_args: nil,
      extra_drive_args: nil, ports: [], control_port: nil,
      debug_port: nil, no_daemonize: false, firmware_format: nil,
      other_default: [], extra_image_opts: nil,
      advanced_network: true, net_mode: :vmnet_shared,
      private_networks: [{ ip: "192.168.105.10" }],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
    }
  end

  it "skips all network when net_device=nil even with advanced_network=true" do
    subject.start(base_options)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).not_to include("-netdev")
    expect(cmd_str).not_to include("vmnet")
  end

  it "falls back to single NIC when advanced_network=true but private_networks empty" do
    opts = base_options.merge(net_device: "virtio-net-device", private_networks: [])
    subject.start(opts)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).to include("-device virtio-net-device,netdev=net0")
    expect(cmd_str).not_to include("net1")
  end

  it "handles empty ports array" do
    opts = base_options.merge(net_device: "virtio-net-device", ports: [],
                              advanced_network: false, private_networks: [])
    subject.start(opts)
    cmd_str = @captured_cmd.join(" ")
    expect(cmd_str).to include("hostfwd=tcp::50022-:22")
    # No extra hostfwd entries
    expect(cmd_str.scan("hostfwd=").length).to eq 1
  end
end
