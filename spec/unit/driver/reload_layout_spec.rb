require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "reload of a VM an older version started" do
  let(:vm_id) { "vq_testid123" }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      @tmp_base = dir.join("tmp")
      FileUtils.mkdir_p(@data_dir.join(vm_id))
      FileUtils.touch(@data_dir.join(vm_id, "linked-box.img"))
      example.run
    end
  end

  subject { described_class.new(vm_id, @data_dir, @tmp_base) }

  let(:legacy_dir) { @tmp_base.join("vagrant-qemu", vm_id) }
  let(:options) do
    {
      ssh_port: 50023, arch: "x86_64", machine: "q35", cpu: "max", smp: "2", memory: "1G",
      net_device: "virtio-net-pci", drive_interface: "virtio", qemu_bin: nil,
      extra_qemu_args: [], extra_netdev_args: nil, extra_drive_args: nil, ports: [],
      control_port: nil, debug_port: nil, no_daemonize: false, firmware_format: nil,
      other_default: [], extra_image_opts: nil, advanced_network: false,
      net_mode: :auto, private_networks: [],
    }
  end

  after { @pids&.each { |pid| kill_fake_qemu(pid) } }

  it "stops it from the tmp layout and starts it under the project-local one on the same driver" do
    @pids = [spawn_fake_qemu(legacy_dir.join("qemu.pid"))]
    File.write(legacy_dir.join("options.yml"), { ssh_port: 50022, control_port: nil }.to_yaml)
    expect(subject.get_ssh_port(2222)).to eq 50022

    # The guest powers off: QEMU exits and removes its pidfile.
    allow(subject).to receive(:send_monitor) do |_opts, _command|
      kill_fake_qemu(@pids.first)
      sleep 0.2
      File.delete(legacy_dir.join("qemu.pid"))
      true
    end
    subject.stop(control_port: nil, graceful_timeout: 5)
    expect(subject.running?).to eq false
    expect(legacy_dir.join("options.yml")).not_to exist

    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu-system-x86_64")
    allow(subject).to receive(:execute) do |*cmd, **_opts|
      @pids << spawn_fake_qemu(cmd[cmd.index("-pidfile") + 1])
      ""
    end
    subject.start(options)

    expect(subject.running?).to eq true
    expect(subject.get_ssh_port(2222)).to eq 50023
    expect(legacy_dir.join("qemu.pid")).not_to exist
  end
end
