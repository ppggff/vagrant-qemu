require "spec_helper"

describe "open issue regressions" do
  describe "firmware paths during macOS cross-architecture emulation (#59/#50)" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("QEMU_DIR").and_return(nil)
      allow(ENV).to receive(:[]).with("HOMEBREW_PREFIX").and_return(nil)
      allow(RbConfig::CONFIG).to receive(:[]).and_call_original
      allow(RbConfig::CONFIG).to receive(:[]).with("host_os").and_return("darwin")
    end

    { "aarch64" => ["x86_64", "/opt/homebrew/share/qemu"],
      "x86_64" => ["aarch64", "/usr/local/share/qemu"] }.each do |host, (guest, path)|
      it "uses the #{host} host's Homebrew installation for a #{guest} guest" do
        config = VagrantPlugins::QEMU::Config.new
        allow(config).to receive(:host_arch).and_return(host)
        config.arch = guest
        config.finalize!
        expect(config.qemu_dir).to eq path
        expect(config.machine).to include("accel=tcg")
        expect(config.cpu).to eq "max"
      end
    end
  end


end
