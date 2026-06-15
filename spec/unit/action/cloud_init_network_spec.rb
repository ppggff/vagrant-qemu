require "spec_helper"
require "vagrant-qemu/action/cloud_init_network"

describe VagrantPlugins::QEMU::Action::CloudInitNetwork do
  let(:app) { lambda { |env| } }
  let(:ui) { double("ui", info: nil, warn: nil) }
  let(:host) { double("host") }
  let(:vagrant_env) { double("vagrant_env", host: host) }
  let(:vm_config) { double("vm_config") }
  let(:machine) { double("machine") }

  let(:private_network_opts) { { ip: "192.168.105.10", netmask: "255.255.255.0" } }
  let(:networks) { [[:private_network, private_network_opts]] }
  let(:advanced_network) { true }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      FileUtils.mkdir_p(@data_dir)
      example.run
    end
  end

  before do
    config_obj = VagrantPlugins::QEMU::Config.new
    config_obj.advanced_network = advanced_network
    config_obj.finalize!

    allow(machine).to receive(:provider_config).and_return(config_obj)
    allow(machine).to receive(:id).and_return("vq_abc123")
    allow(machine).to receive(:data_dir).and_return(@data_dir)
    allow(machine).to receive(:config).and_return(double("config", vm: vm_config))

    allow(vm_config).to receive(:networks).and_return(networks)
    allow(vm_config).to receive(:cloud_init_configs).and_return([])
    allow(vm_config).to receive(:disk)
    allow(vm_config).to receive(:disks).and_return([])

    allow(host).to receive(:capability?).with(:create_iso).and_return(true)

    @seed_files = nil
    @iso_destination = nil
    @create_iso_calls = 0
    allow(host).to receive(:capability) do |cap, source_dir, opts|
      expect(cap).to eq :create_iso
      @create_iso_calls += 1
      @iso_destination = opts[:file_destination]
      # Capture the seed contents before the action removes the temp dir
      @seed_files = Dir.children(source_dir).sort.each_with_object({}) do |f, h|
        h[f] = File.read(Pathname.new(source_dir).join(f))
      end
      FileUtils.touch(opts[:file_destination])
      Pathname.new(opts[:file_destination])
    end
  end

  let(:env) { { machine: machine, ui: ui, env: vagrant_env } }

  def run_action
    described_class.new(app, env).call(env)
  end

  it "builds a seed with network-config, meta-data and user-data" do
    run_action
    expect(@seed_files.keys).to contain_exactly("meta-data", "network-config", "user-data")

    parsed = YAML.safe_load(@seed_files["network-config"])
    expect(parsed["network"]["version"]).to eq 2
    expect(parsed["network"]["ethernets"]["private-nic"]["addresses"]).to eq ["192.168.105.10/24"]

    meta = YAML.safe_load(@seed_files["meta-data"])
    expect(meta["instance-id"]).to eq "i-vq_abc123"
  end

  it "uses the same MAC pair as the driver command line" do
    run_action
    mac0, mac1 = VagrantPlugins::QEMU::Network.nic_macs("vq_abc123", private_network_opts)
    parsed = YAML.safe_load(@seed_files["network-config"])
    expect(parsed["network"]["ethernets"]["user-nic"]["match"]["macaddress"]).to eq mac0
    expect(parsed["network"]["ethernets"]["private-nic"]["match"]["macaddress"]).to eq mac1
  end

  it "honors a user-specified MAC" do
    private_network_opts[:mac] = "52:54:00:aa:bb:cc"
    run_action
    parsed = YAML.safe_load(@seed_files["network-config"])
    expect(parsed["network"]["ethernets"]["private-nic"]["match"]["macaddress"]).to eq "52:54:00:aa:bb:cc"
  end

  it "attaches the ISO as a dvd disk" do
    run_action
    expect(vm_config).to have_received(:disk).with(
      :dvd, hash_including(name: "vagrant-qemu-network-disk")
    )
  end

  context "when core CloudInitSetup already built a user-data seed" do
    let(:core_iso) { @data_dir.join("vagrant-cloud_init.iso").to_s }
    let(:core_disk) do
      double("disk", type: :dvd, name: "vagrant-cloud_init-disk", file: core_iso)
    end

    before do
      FileUtils.touch(core_iso)
      allow(vm_config).to receive(:cloud_init_configs)
        .and_return([double("cloud_init_cfg", type: :user_data)])
      allow(vm_config).to receive(:disks).and_return([core_disk])
      allow_any_instance_of(Vagrant::Action::Builtin::CloudInitSetup)
        .to receive(:setup_user_data).and_return("#cloud-config\nruncmd: [echo hi]\n")
    end

    it "rebuilds the existing seed in place with all three files" do
      run_action
      expect(@create_iso_calls).to eq 1
      expect(@iso_destination.to_s).to eq core_iso
      expect(@seed_files.keys).to contain_exactly("meta-data", "network-config", "user-data")
    end

    it "carries the core user-data into the merged seed" do
      run_action
      expect(@seed_files["user-data"]).to eq "#cloud-config\nruncmd: [echo hi]\n"
      parsed = YAML.safe_load(@seed_files["network-config"])
      expect(parsed["network"]["ethernets"]["private-nic"]["addresses"]).to eq ["192.168.105.10/24"]
    end

    it "does not register a second disk" do
      run_action
      expect(vm_config).not_to have_received(:disk)
    end
  end

  it "raises when the host cannot build ISOs" do
    allow(host).to receive(:capability?).with(:create_iso).and_return(false)
    expect { run_action }.to raise_error(Vagrant::Errors::CreateIsoHostCapNotFound)
  end

  context "when advanced_network is disabled" do
    let(:advanced_network) { false }

    it "does nothing" do
      run_action
      expect(host).not_to have_received(:capability)
      expect(vm_config).not_to have_received(:disk)
    end
  end

  context "without a private_network ip" do
    let(:networks) { [[:private_network, { netmask: "255.255.255.0" }]] }

    it "does nothing" do
      run_action
      expect(host).not_to have_received(:capability)
    end
  end

  it "calls the next middleware" do
    called = false
    action = described_class.new(lambda { |_| called = true }, env)
    action.call(env)
    expect(called).to be true
  end
end
