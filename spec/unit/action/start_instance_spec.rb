require "spec_helper"

describe VagrantPlugins::QEMU::Action::StartInstance do
  let(:app) { double("app", call: nil) }

  it "preserves launch failures when there are no VirtioFS shares" do
    ctx = mock_vagrant_env
    error = RuntimeError.new("launch failed")
    allow(ctx[:driver]).to receive(:start).and_raise(error)
    expect { described_class.new(app, ctx[:env]).call(ctx[:env]) }.to raise_error(error)
  end

  it "marks VirtioFS daemon logs as shown after printing them for a failed launch" do
    with_temp_dir do |dir|
      ctx = mock_vagrant_env(provider_config_overrides: {
        memory: "1G", virtiofs_qemu_args: ["-device", "vhost-user-fs-pci"]
      })
      allow(ctx[:machine]).to receive(:data_dir).and_return(dir)
      FileUtils.mkdir_p(dir.join("virtiofs"))
      File.write(dir.join("virtiofs/virtiofs0.log"), "diagnostic")
      allow(ctx[:ui]).to receive(:error)
      allow(ctx[:driver]).to receive(:start).and_raise("launch failed")
      expect { described_class.new(app, ctx[:env]).call(ctx[:env]) }.to raise_error("launch failed")
      expect(ctx[:ui]).to have_received(:error).with(/virtiofsd log .*\ndiagnostic/m)
      expect(ctx[:env][:virtiofs_logs_shown]).to eq true
    end
  end

  it "uses the aligned VirtioFS backend size for guest RAM" do
    ctx = mock_vagrant_env(provider_config_overrides: {
      memory: "1.3G", virtiofs_qemu_args: ["-object", "memory-backend-file,id=mem,size=1332M"]
    })
    expect(ctx[:driver]).to receive(:start).with(hash_including(memory: "1332M"))
    described_class.new(app, ctx[:env]).call(ctx[:env])
  end

  it "passes all config options to driver.start" do
    ctx = mock_vagrant_env(
      provider_config_overrides: { memory: "8G", advanced_network: true, net_mode: :vmnet_shared },
      networks: [[:forwarded_port, { id: "ssh", host: 50022, guest: 22, protocol: "tcp" }]]
    )
    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(received_options[:memory]).to eq "8G"
    expect(received_options[:advanced_network]).to eq true
    expect(received_options[:net_mode]).to eq :vmnet_shared
  end

  it "collects private_networks from vm.networks" do
    ctx = mock_vagrant_env(
      networks: [
        [:forwarded_port, { id: "ssh", host: 50022, guest: 22, protocol: "tcp" }],
        [:private_network, { ip: "192.168.105.10", netmask: "255.255.255.0" }],
      ]
    )
    received_options = nil
    allow(ctx[:driver]).to receive(:start) { |opts| received_options = opts }

    action = described_class.new(app, ctx[:env])
    action.call(ctx[:env])

    expect(received_options[:private_networks]).to eq [{ ip: "192.168.105.10", netmask: "255.255.255.0" }]
  end

  describe "#forwarded_ports" do
    it "skips SSH port" do
      ctx = mock_vagrant_env(networks: [
        [:forwarded_port, { id: "ssh", host: 50022, guest: 22, protocol: "tcp" }],
        [:forwarded_port, { host: 8080, guest: 80, protocol: "tcp", host_ip: "", guest_ip: "" }],
      ])
      allow(ctx[:driver]).to receive(:start)

      action = described_class.new(app, ctx[:env])
      ports = action.forwarded_ports(ctx[:env])

      expect(ports.length).to eq 1
      expect(ports.first).to include("8080")
    end

    it "skips disabled ports" do
      ctx = mock_vagrant_env(networks: [
        [:forwarded_port, { host: 8080, guest: 80, disabled: true, protocol: "tcp", host_ip: "", guest_ip: "" }],
      ])

      action = described_class.new(app, ctx[:env])
      ports = action.forwarded_ports(ctx[:env])

      expect(ports).to be_empty
    end
  end
  describe "direct SSH with the default NIC disabled" do
    it "ignores an inherited corrected SSH port when there is no provider NIC" do
      ctx = mock_vagrant_env(provider_config_overrides: { net_device: nil, ssh_port: 22 },
        networks: [[:forwarded_port, { id: "ssh", host: 2200, guest: 22 }]])
      options = nil
      allow(ctx[:driver]).to receive(:start) { |opts| options = opts }
      VagrantPlugins::QEMU::Action::StartInstance.new(app, ctx[:env]).call(ctx[:env])
      expect(options[:ssh_port]).to eq 22
    end
  end

end
