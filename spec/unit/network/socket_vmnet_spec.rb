require "spec_helper"

describe VagrantPlugins::QEMU::Network::SocketVmnet do
  subject { described_class.new }

  let(:sock) { "/opt/homebrew/var/run/socket_vmnet" }
  let(:client) { "/opt/homebrew/opt/socket_vmnet/bin/socket_vmnet_client" }

  context "stream route (use_stream: true)" do
    let(:opts) { { use_stream: true, socket_vmnet_socket: sock, socket_vmnet_client: client } }

    it "builds a native stream netdev connecting to the daemon socket" do
      expect(subject.build_netdev_args("net1", opts))
        .to eq %W(-netdev stream,id=net1,server=off,addr.type=unix,addr.path=#{sock})
    end

    it "needs no launch wrapper" do
      expect(subject.launch_prefix(opts)).to eq []
    end
  end

  context "wrapper route (use_stream: false)" do
    let(:opts) { { use_stream: false, socket_vmnet_socket: sock, socket_vmnet_client: client } }

    it "builds a socket netdev on fd 3" do
      expect(subject.build_netdev_args("net1", opts)).to eq %w(-netdev socket,id=net1,fd=3)
    end

    it "prepends the socket_vmnet_client wrapper with the socket path" do
      expect(subject.launch_prefix(opts)).to eq [client, sock]
    end
  end

  it "never requires sudo (the daemon holds the root vmnet membership)" do
    expect(subject.requires_sudo?).to eq false
  end
end

describe VagrantPlugins::QEMU::Network::Base, "#launch_prefix" do
  it "defaults to an empty prefix (other backends launch qemu directly)" do
    expect(described_class.new.launch_prefix({})).to eq []
    expect(VagrantPlugins::QEMU::Network::Vmnet.new.launch_prefix({})).to eq []
  end
end

describe VagrantPlugins::QEMU::Network, ".qemu_supports_stream?" do
  # Reset the memoized cache between examples.
  before { described_class.instance_variable_set(:@stream_support, nil) }

  def stub_probe(stdout:, exit_code: 0)
    result = ::Vagrant::Util::Subprocess::Result.new(exit_code, stdout, "")
    allow(::Vagrant::Util::Subprocess).to receive(:execute)
      .with("qemu-x", "-M", "none", "-netdev", "help").and_return(result)
  end

  it "is true when the netdev list contains a stream line" do
    stub_probe(stdout: "socket\nstream\ndgram\nuser\n")
    expect(described_class.qemu_supports_stream?("qemu-x")).to eq true
  end

  it "is false when the list lacks stream (old QEMU)" do
    stub_probe(stdout: "socket\nuser\ntap\n")
    expect(described_class.qemu_supports_stream?("qemu-x")).to eq false
  end

  it "is nil (unknown) when the probe exits non-zero" do
    stub_probe(stdout: "stream\n", exit_code: 1)
    expect(described_class.qemu_supports_stream?("qemu-x")).to be_nil
  end

  it "is nil (not an exception) when the probe cannot run" do
    allow(::Vagrant::Util::Subprocess).to receive(:execute).and_raise(StandardError.new("boom"))
    expect(described_class.qemu_supports_stream?("qemu-x")).to be_nil
  end

  it "caches the result per binary (probes once)" do
    stub_probe(stdout: "stream\n")
    described_class.qemu_supports_stream?("qemu-x")
    described_class.qemu_supports_stream?("qemu-x")
    expect(::Vagrant::Util::Subprocess).to have_received(:execute).once
  end
end
