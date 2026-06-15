require_relative "helper"
require "vagrant-qemu/action/cloud_init_network"

describe "advanced network configuration", :acceptance do
  around(:each) do |example|
    with_temp_dir do |dir|
      @dir = dir
      @bin_dir = create_fake_qemu(dir)
      example.run
    end
  end

  def start_driver(vm_id, **option_overrides)
    data_dir = @dir.join("data")
    tmp_base = @dir.join("tmp")
    FileUtils.mkdir_p(data_dir.join(vm_id))
    FileUtils.mkdir_p(tmp_base)
    FileUtils.touch(data_dir.join(vm_id, "linked-box.img"))

    driver = VagrantPlugins::QEMU::Driver.new(vm_id, data_dir, tmp_base)
    captured_cmd = nil
    allow(driver).to receive(:execute) { |*cmd, **_opts| captured_cmd = cmd; "" }
    allow(driver).to receive(:running?).and_return(false)
    allow(Vagrant::Util::Which).to receive(:which).and_return("/usr/bin/qemu")

    driver.start({
      ssh_host: "127.0.0.1", ssh_port: 50022, arch: "aarch64",
      machine: nil, cpu: nil, smp: nil, memory: nil,
      net_device: "virtio-net-device", drive_interface: nil,
      qemu_bin: nil, extra_qemu_args: [], extra_netdev_args: nil,
      extra_drive_args: nil, ports: [], control_port: nil,
      debug_port: nil, no_daemonize: false, firmware_format: nil,
      other_default: [], extra_image_opts: nil,
      advanced_network: false, net_mode: :auto, private_networks: [],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
    }.merge(option_overrides))

    [captured_cmd, tmp_base]
  end

  # Runs the CloudInitNetwork action for a Vagrantfile-like private_network
  # config and returns the seed files passed to the :create_iso capability.
  def run_cloud_init_network_action(vm_id, pn_opts)
    config_obj = VagrantPlugins::QEMU::Config.new
    config_obj.advanced_network = true
    config_obj.finalize!

    data_dir = @dir.join("machine_data")
    FileUtils.mkdir_p(data_dir)

    vm_config = double("vm_config")
    allow(vm_config).to receive(:networks).and_return([[:private_network, pn_opts]])
    allow(vm_config).to receive(:cloud_init_configs).and_return([])
    allow(vm_config).to receive(:disk)
    allow(vm_config).to receive(:disks).and_return([])

    machine = double("machine")
    allow(machine).to receive(:provider_config).and_return(config_obj)
    allow(machine).to receive(:id).and_return(vm_id)
    allow(machine).to receive(:data_dir).and_return(data_dir)
    allow(machine).to receive(:config).and_return(double("config", vm: vm_config))

    seed_files = nil
    host = double("host")
    allow(host).to receive(:capability?).with(:create_iso).and_return(true)
    allow(host).to receive(:capability) do |_cap, source_dir, opts|
      seed_files = Dir.children(source_dir).sort.each_with_object({}) do |f, h|
        h[f] = File.read(Pathname.new(source_dir).join(f))
      end
      FileUtils.touch(opts[:file_destination])
      Pathname.new(opts[:file_destination])
    end

    env = {
      machine: machine,
      ui: double("ui", info: nil, warn: nil),
      env: double("vagrant_env", host: host),
    }
    VagrantPlugins::QEMU::Action::CloudInitNetwork.new(lambda { |_| }, env).call(env)

    seed_files
  end

  it "keeps the single-NIC command line when advanced_network=false" do
    cmd, tmp_base = start_driver("vq_test_nonet",
      private_networks: [{ ip: "192.168.105.10" }])

    cmd_str = cmd.join(" ")
    expect(cmd_str).to include("-netdev user,id=net0")
    expect(cmd_str).not_to include("net1")
    expect(tmp_base.join("vagrant-qemu", "vq_test_nonet", "network-config")).not_to exist
  end

  it "builds dual-NIC command line when advanced_network=true with private_network" do
    cmd, _ = start_driver("vq_test_advnet",
      advanced_network: true, net_mode: :vmnet_shared,
      private_networks: [{ ip: "192.168.105.10", netmask: "255.255.255.0" }])

    cmd_str = cmd.join(" ")
    expect(cmd_str).to include("-netdev user,id=net0")
    expect(cmd_str).to include("-netdev vmnet-shared,id=net1")
  end

  it "seed network-config matches the QEMU command line MACs and IP" do
    pn = { ip: "10.0.0.5", netmask: "255.255.0.0" }
    vm_id = "vq_test_netcfg"

    cmd, _ = start_driver(vm_id,
      advanced_network: true, net_mode: :vmnet_shared, private_networks: [pn])
    cmd_macs = cmd.join(" ").scan(/mac=(\h\h(?::\h\h){5})/).flatten

    seed = run_cloud_init_network_action(vm_id, pn)
    parsed = YAML.safe_load(seed["network-config"])
    user_nic = parsed["network"]["ethernets"]["user-nic"]
    priv_nic = parsed["network"]["ethernets"]["private-nic"]

    # The seed must address the exact NICs the driver creates — MAC-matched,
    # never order-based.
    expect([user_nic["match"]["macaddress"], priv_nic["match"]["macaddress"]]).to eq cmd_macs
    expect(user_nic["dhcp4"]).to eq true
    expect(priv_nic["addresses"]).to eq ["10.0.0.5/16"]
  end

  it "skips network entirely when net_device=nil even with advanced_network" do
    cmd, tmp_base = start_driver("vq_test_nodev",
      net_device: nil, advanced_network: true, net_mode: :vmnet_shared,
      private_networks: [{ ip: "192.168.105.10" }])

    cmd_str = cmd.join(" ")
    expect(cmd_str).not_to include("-netdev")
    expect(cmd_str).not_to include("vmnet")
    expect(tmp_base.join("vagrant-qemu", "vq_test_nodev", "network-config")).not_to exist
  end
end
