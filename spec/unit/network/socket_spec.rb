require "spec_helper"

describe VagrantPlugins::QEMU::Network::Socket do
  subject { described_class.new }

  context "backward-compatible multicast default (no socket_opts)" do
    it "builds socket args with the default mcast address" do
      args = subject.build_netdev_args("net1", {})
      expect(args).to eq %w(-netdev socket,id=net1,mcast=230.0.0.1:1234)
    end

    it "honors mcast_addr" do
      args = subject.build_netdev_args("net1", mcast_addr: "230.0.0.2:5678")
      expect(args).to eq %w(-netdev socket,id=net1,mcast=230.0.0.2:5678)
    end
  end

  context "user-supplied socket_opts (verbatim, plugin does not interpret)" do
    it "emits multicast opts as given" do
      args = subject.build_netdev_args("net1", socket_opts: "mcast=230.0.0.9:9999")
      expect(args).to eq %w(-netdev socket,id=net1,mcast=230.0.0.9:9999)
    end

    it "emits a listen netdev when the user asks to listen" do
      args = subject.build_netdev_args("net1", socket_opts: "listen=127.0.0.1:12399")
      expect(args).to eq %w(-netdev socket,id=net1,listen=127.0.0.1:12399)
    end

    it "emits a connect netdev when the user asks to connect" do
      args = subject.build_netdev_args("net1", socket_opts: "connect=127.0.0.1:12399")
      expect(args).to eq %w(-netdev socket,id=net1,connect=127.0.0.1:12399)
    end

    it "takes precedence over mcast_addr" do
      args = subject.build_netdev_args("net1", socket_opts: "listen=:1234", mcast_addr: "230.0.0.2:5678")
      expect(args).to eq %w(-netdev socket,id=net1,listen=:1234)
    end

    it "falls back to mcast when socket_opts is empty" do
      args = subject.build_netdev_args("net1", socket_opts: "")
      expect(args).to eq %w(-netdev socket,id=net1,mcast=230.0.0.1:1234)
    end
  end
end
