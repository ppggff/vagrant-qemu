require "spec_helper"

describe VagrantPlugins::QEMU::Config do
  subject { described_class.new }

  # Build a config with the host detection stubbed, then finalize.
  def finalized(host_arch:, host_accel:, arch: nil)
    config = described_class.new
    allow(config).to receive(:host_arch).and_return(host_arch)
    allow(config).to receive(:host_accel).and_return(host_accel)
    config.arch = arch unless arch.nil?
    config.finalize!
    config
  end

  describe "defaults (host-aware)" do
    context "native arm64 macOS (Apple Silicon)" do
      subject { finalized(host_arch: "aarch64", host_accel: "hvf") }

      its(:arch) { is_expected.to eq "aarch64" }
      its(:machine) { is_expected.to eq "virt,highmem=on,accel=hvf" }
      its(:cpu) { is_expected.to eq "host" }
      its(:net_device) { is_expected.to eq "virtio-net-device" }
    end

    context "native x86_64 macOS (Intel)" do
      subject { finalized(host_arch: "x86_64", host_accel: "hvf") }

      its(:arch) { is_expected.to eq "x86_64" }
      its(:machine) { is_expected.to eq "q35,accel=hvf" }
      its(:cpu) { is_expected.to eq "host" }
      its(:net_device) { is_expected.to eq "virtio-net-pci" }
    end

    context "native x86_64 Linux" do
      subject { finalized(host_arch: "x86_64", host_accel: "kvm") }

      its(:machine) { is_expected.to eq "q35,accel=kvm" }
      its(:cpu) { is_expected.to eq "host" }
    end

    context "emulation: x86_64 guest on an arm64 host" do
      subject { finalized(host_arch: "aarch64", host_accel: "hvf", arch: "x86_64") }

      its(:machine) { is_expected.to eq "q35,accel=tcg" }
      its(:cpu) { is_expected.to eq "max" }
      its(:net_device) { is_expected.to eq "virtio-net-pci" }
    end

    it "ssh_port stays 50022 regardless of host" do
      expect(finalized(host_arch: "x86_64", host_accel: "kvm").ssh_port).to eq 50022
    end
  end

  describe "#default_qemu_dir" do
    it "honors QEMU_DIR above everything" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("QEMU_DIR").and_return("/custom/qemu")
      expect(subject.send(:default_qemu_dir, "x86_64")).to eq "/custom/qemu"
    end

    it "derives from HOMEBREW_PREFIX when QEMU_DIR is unset" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("QEMU_DIR").and_return(nil)
      allow(ENV).to receive(:[]).with("HOMEBREW_PREFIX").and_return("/opt/hb")
      expect(subject.send(:default_qemu_dir, "x86_64")).to eq "/opt/hb/share/qemu"
    end

    context "platform default (no env overrides)" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("QEMU_DIR").and_return(nil)
        allow(ENV).to receive(:[]).with("HOMEBREW_PREFIX").and_return(nil)
      end

      it "uses arch-specific Homebrew paths on macOS" do
        skip "darwin-only assertion" unless RbConfig::CONFIG["host_os"] =~ /darwin/
        expect(subject.send(:default_qemu_dir, "aarch64")).to eq "/opt/homebrew/share/qemu"
        expect(subject.send(:default_qemu_dir, "x86_64")).to eq "/usr/local/share/qemu"
      end
    end
  end

  describe "ssh_port string to integer" do
    it "converts string to integer" do
      config = described_class.new
      config.ssh_port = "50022"
      config.finalize!
      expect(config.ssh_port).to eq 50022
    end
  end

  describe "merge" do
    it "preserves custom values" do
      subject.finalize!
      other = described_class.new
      other.memory = "8G"
      other.finalize!

      result = subject.merge(other)
      expect(result.memory).to eq "8G"
    end
  end

  describe "explicit values are never overridden by defaults" do
    it "keeps machine as nil after finalize (omits the -machine arg)" do
      config = described_class.new
      config.machine = nil
      config.finalize!
      expect(config.machine).to be_nil
    end

    it "keeps a user-specified cpu" do
      config = described_class.new
      config.cpu = "qemu64"
      config.finalize!
      expect(config.cpu).to eq "qemu64"
    end

    it "keeps a user-specified qemu_dir" do
      config = described_class.new
      config.qemu_dir = "/somewhere/else"
      config.finalize!
      expect(config.qemu_dir).to eq "/somewhere/else"
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
