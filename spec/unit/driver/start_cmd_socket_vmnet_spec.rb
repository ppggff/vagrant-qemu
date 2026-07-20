require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "start command line (socket_vmnet)" do
  let(:vm_id) { "vq_svtest00042" }

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

      # Real socket + client files so File.exist?/executable? preconditions pass.
      @sock = @data_dir.join("socket_vmnet").to_s
      FileUtils.touch(@sock)
      @client = @data_dir.join("socket_vmnet_client").to_s
      FileUtils.touch(@client)
      File.chmod(0o755, @client)

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
      extra_image_opts: nil,
      advanced_network: true, net_mode: :socket_vmnet,
      private_networks: [{ ip: "192.168.105.10", netmask: "255.255.255.0" }],
      vmnet_interface: "en0", tap_device: nil, mcast_addr: nil,
      socket_vmnet_socket: nil, socket_vmnet_client: nil,
    }
  end

  before do
    @captured_cmd = nil
    allow(subject).to receive(:execute) do |*cmd, **opts|
      @captured_cmd = cmd
      ""
    end
    allow(subject).to receive(:running?).and_return(false)
    # qemu binary resolves; client path is checked via File.executable? (Which -> nil).
    allow(Vagrant::Util::Which).to receive(:which).and_return(nil)
    allow(Vagrant::Util::Which).to receive(:which)
      .with("qemu-system-aarch64").and_return("/usr/bin/qemu-system-aarch64")
  end

  def options(overrides = {})
    base_options.merge(socket_vmnet_socket: @sock, socket_vmnet_client: @client).merge(overrides)
  end

  context "stream route (QEMU supports stream)" do
    before { allow(VagrantPlugins::QEMU::Network).to receive(:qemu_supports_stream?).and_return(true) }

    it "attaches NIC 1 to the daemon socket via a native stream netdev" do
      subject.start(options)
      cmd_str = @captured_cmd.join(" ")
      expect(cmd_str).to include("-netdev stream,id=net1,server=off,addr.type=unix,addr.path=#{@sock}")
    end

    it "does not wrap qemu (command still begins with the qemu binary)" do
      subject.start(options)
      expect(@captured_cmd.first).to eq "qemu-system-aarch64"
    end

    it "keeps NIC 0 user-mode with SSH hostfwd" do
      subject.start(options)
      expect(@captured_cmd.join(" ")).to include("-netdev user,id=net0,hostfwd=tcp::50022-:22")
    end
  end

  context "wrapper route (QEMU lacks stream)" do
    before { allow(VagrantPlugins::QEMU::Network).to receive(:qemu_supports_stream?).and_return(false) }

    it "prepends the socket_vmnet_client wrapper with the socket path" do
      subject.start(options)
      expect(@captured_cmd[0, 3]).to eq [@client, @sock, "qemu-system-aarch64"]
    end

    it "attaches NIC 1 via a socket netdev on fd 3" do
      subject.start(options)
      expect(@captured_cmd.join(" ")).to include("-netdev socket,id=net1,fd=3")
    end
  end

  context "probe could not run (nil) -> optimistic stream" do
    before { allow(VagrantPlugins::QEMU::Network).to receive(:qemu_supports_stream?).and_return(nil) }

    it "uses the stream route and no wrapper" do
      subject.start(options)
      expect(@captured_cmd.first).to eq "qemu-system-aarch64"
      expect(@captured_cmd.join(" ")).to include("-netdev stream,id=net1")
    end
  end

  context "gating: net_mode set but advanced_network off" do
    it "does not wrap qemu and does not add NIC 1 (matches pre-existing warn behavior)" do
      # No probe should even happen; single-NIC user-mode path.
      expect(VagrantPlugins::QEMU::Network).not_to receive(:qemu_supports_stream?)
      subject.start(options(advanced_network: false))
      cmd_str = @captured_cmd.join(" ")
      expect(@captured_cmd.first).to eq "qemu-system-aarch64"
      expect(cmd_str).not_to include("netdev=net1")
      expect(cmd_str).not_to include("-netdev stream")
      expect(cmd_str).not_to include("fd=3")
    end
  end

  context "preconditions (fail-fast)" do
    it "raises when the daemon socket is missing" do
      allow(VagrantPlugins::QEMU::Network).to receive(:qemu_supports_stream?).and_return(true)
      expect { subject.start(options(socket_vmnet_socket: "/nonexistent/sock")) }
        .to raise_error(VagrantPlugins::QEMU::Errors::SocketVmnetSocketNotFound)
    end

    it "raises on the wrapper route when the client is missing" do
      allow(VagrantPlugins::QEMU::Network).to receive(:qemu_supports_stream?).and_return(false)
      expect { subject.start(options(socket_vmnet_client: "/nonexistent/client")) }
        .to raise_error(VagrantPlugins::QEMU::Errors::SocketVmnetClientNotFound)
    end

    it "raises on non-macOS hosts" do
      allow(RbConfig::CONFIG).to receive(:[]).and_call_original
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("linux-gnu")
      expect { subject.start(options) }
        .to raise_error(VagrantPlugins::QEMU::Errors::SocketVmnetNotMacos)
    end
  end
end
