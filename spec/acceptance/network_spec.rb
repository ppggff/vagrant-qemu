require_relative "helper"

describe "advanced network configuration", :acceptance do
  around(:each) do |example|
    with_temp_dir do |dir|
      @dir = dir
      @bin_dir = create_fake_qemu(dir)
      example.run
    end
  end

  it "does not generate network-config when advanced_network=false" do
    data_dir = @dir.join("data")
    tmp_base = @dir.join("tmp")
    vm_id = "vq_test_nonet"
    FileUtils.mkdir_p(data_dir.join(vm_id))
    FileUtils.mkdir_p(tmp_base)
    FileUtils.touch(data_dir.join(vm_id, "linked-box.img"))

    driver = VagrantPlugins::QEMU::Driver.new(vm_id, data_dir, tmp_base)
    allow(driver).to receive(:execute).and_return("")
    allow(driver).to receive(:running?).and_return(false)
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu")

    driver.start(
      ssh_host: "127.0.0.1", ssh_port: 50022, arch: "aarch64",
      machine: nil, cpu: nil, smp: nil, memory: nil,
      net_device: "virtio-net-device", drive_interface: nil,
      qemu_bin: nil, extra_qemu_args: [], extra_netdev_args: nil,
      extra_drive_args: nil, ports: [], control_port: nil,
      debug_port: nil, no_daemonize: false, firmware_format: nil,
      other_default: [], extra_image_opts: nil,
      advanced_network: false, net_mode: :auto, private_networks: [],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
    )

    config_file = tmp_base.join("vagrant-qemu", vm_id, "network-config")
    expect(config_file).not_to exist
  end

  it "generates network-config when advanced_network=true with private_network" do
    data_dir = @dir.join("data")
    tmp_base = @dir.join("tmp")
    vm_id = "vq_test_advnet"
    FileUtils.mkdir_p(data_dir.join(vm_id))
    FileUtils.mkdir_p(tmp_base)
    FileUtils.touch(data_dir.join(vm_id, "linked-box.img"))

    driver = VagrantPlugins::QEMU::Driver.new(vm_id, data_dir, tmp_base)
    allow(driver).to receive(:execute).and_return("")
    allow(driver).to receive(:running?).and_return(false)
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu")

    driver.start(
      ssh_host: "127.0.0.1", ssh_port: 50022, arch: "aarch64",
      machine: nil, cpu: nil, smp: nil, memory: nil,
      net_device: "virtio-net-device", drive_interface: nil,
      qemu_bin: nil, extra_qemu_args: [], extra_netdev_args: nil,
      extra_drive_args: nil, ports: [], control_port: nil,
      debug_port: nil, no_daemonize: false, firmware_format: nil,
      other_default: [], extra_image_opts: nil,
      advanced_network: true, net_mode: :vmnet_shared,
      private_networks: [{ ip: "192.168.105.10", netmask: "255.255.255.0" }],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
    )

    config_file = tmp_base.join("vagrant-qemu", vm_id, "network-config")
    expect(config_file).to exist
  end

  it "network-config contains correct MAC addresses and IP" do
    data_dir = @dir.join("data")
    tmp_base = @dir.join("tmp")
    vm_id = "vq_test_netcfg"
    FileUtils.mkdir_p(data_dir.join(vm_id))
    FileUtils.mkdir_p(tmp_base)
    FileUtils.touch(data_dir.join(vm_id, "linked-box.img"))

    driver = VagrantPlugins::QEMU::Driver.new(vm_id, data_dir, tmp_base)
    allow(driver).to receive(:execute).and_return("")
    allow(driver).to receive(:running?).and_return(false)
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu")

    driver.start(
      ssh_host: "127.0.0.1", ssh_port: 50022, arch: "aarch64",
      machine: nil, cpu: nil, smp: nil, memory: nil,
      net_device: "virtio-net-device", drive_interface: nil,
      qemu_bin: nil, extra_qemu_args: [], extra_netdev_args: nil,
      extra_drive_args: nil, ports: [], control_port: nil,
      debug_port: nil, no_daemonize: false, firmware_format: nil,
      other_default: [], extra_image_opts: nil,
      advanced_network: true, net_mode: :vmnet_shared,
      private_networks: [{ ip: "10.0.0.5", netmask: "255.255.0.0" }],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
    )

    config_file = tmp_base.join("vagrant-qemu", vm_id, "network-config")
    parsed = YAML.safe_load(File.read(config_file))

    user_nic = parsed["network"]["ethernets"]["user-nic"]
    priv_nic = parsed["network"]["ethernets"]["private-nic"]

    expect(user_nic["match"]["macaddress"]).to match(/52:54:00/)
    expect(user_nic["dhcp4"]).to eq true
    expect(priv_nic["match"]["macaddress"]).to match(/52:54:00/)
    expect(priv_nic["addresses"]).to eq ["10.0.0.5/16"]
    # MACs should be different
    expect(user_nic["match"]["macaddress"]).not_to eq priv_nic["match"]["macaddress"]
  end

  it "skips network entirely when net_device=nil even with advanced_network" do
    data_dir = @dir.join("data")
    tmp_base = @dir.join("tmp")
    vm_id = "vq_test_nodev"
    FileUtils.mkdir_p(data_dir.join(vm_id))
    FileUtils.mkdir_p(tmp_base)
    FileUtils.touch(data_dir.join(vm_id, "linked-box.img"))

    driver = VagrantPlugins::QEMU::Driver.new(vm_id, data_dir, tmp_base)
    captured_cmd = nil
    allow(driver).to receive(:execute) { |*cmd, **opts| captured_cmd = cmd; "" }
    allow(driver).to receive(:running?).and_return(false)
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu")

    driver.start(
      ssh_host: "127.0.0.1", ssh_port: 50022, arch: "aarch64",
      machine: nil, cpu: nil, smp: nil, memory: nil,
      net_device: nil, drive_interface: nil,
      qemu_bin: nil, extra_qemu_args: [], extra_netdev_args: nil,
      extra_drive_args: nil, ports: [], control_port: nil,
      debug_port: nil, no_daemonize: false, firmware_format: nil,
      other_default: [], extra_image_opts: nil,
      advanced_network: true, net_mode: :vmnet_shared,
      private_networks: [{ ip: "192.168.105.10" }],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
    )

    cmd_str = captured_cmd.join(" ")
    expect(cmd_str).not_to include("-netdev")
    expect(cmd_str).not_to include("vmnet")

    config_file = tmp_base.join("vagrant-qemu", vm_id, "network-config")
    expect(config_file).not_to exist
  end
end
