require "spec_helper"

describe VagrantPlugins::QEMU::Config do
  subject { described_class.new }

  before { subject.finalize! }

  describe "defaults" do
    its(:ssh_port) { is_expected.to eq 50022 }
    its(:arch) { is_expected.to eq "aarch64" }
    its(:machine) { is_expected.to eq "virt,accel=hvf,highmem=on" }
    its(:cpu) { is_expected.to eq "host" }
    its(:advanced_network) { is_expected.to eq false }
    its(:net_mode) { is_expected.to eq :auto }
    its(:vmnet_interface) { is_expected.to eq "en0" }
  end

  describe "ssh_port string to integer" do
    before do
      subject = described_class.new
      subject.ssh_port = "50022"
      subject.finalize!
      @config = subject
    end

    it "converts string to integer" do
      expect(@config.ssh_port).to eq 50022
    end
  end

  describe "merge" do
    it "preserves custom values" do
      other = described_class.new
      other.memory = "8G"
      other.finalize!

      result = subject.merge(other)
      expect(result.memory).to eq "8G"
    end
  end

  describe "nil values preserved" do
    it "keeps machine as nil after finalize" do
      config = described_class.new
      config.machine = nil
      config.finalize!
      expect(config.machine).to be_nil
    end
  end

  describe "advanced network options" do
    it "preserves advanced_network=true" do
      config = described_class.new
      config.advanced_network = true
      config.finalize!
      expect(config.advanced_network).to eq true
    end

    it "preserves custom net_mode" do
      config = described_class.new
      config.net_mode = :vmnet_shared
      config.finalize!
      expect(config.net_mode).to eq :vmnet_shared
    end
  end
end
