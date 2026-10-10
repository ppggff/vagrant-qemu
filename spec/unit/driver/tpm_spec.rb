require "spec_helper"

RSpec.describe "Provider-owned TPM policy" do
  it "rejects nonboolean TPM requests before creating Machine state" do
    with_temp_dir do |dir|
      driver = VagrantPlugins::QEMU::Driver.new("vq_invalid", dir.join("data"), dir.join("tmp"))
      expect { driver.start(tpm: "true", arch: "x86_64") }
        .to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
      expect(dir.join("data", "vq_invalid")).not_to exist
      expect(dir.join("tmp", "vagrant-qemu", "vq_invalid")).not_to exist
    end
  end

  it "rejects Windows TPM before an emulator or QEMU can launch" do
    allow(Vagrant::Util::Platform).to receive(:windows?).and_return(true)
    with_temp_dir do |dir|
      driver = VagrantPlugins::QEMU::Driver.new("vq_invalid", dir.join("data"), dir.join("tmp"))
      expect { driver.start(tpm: true, arch: "x86_64") }
        .to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
      expect(dir.join("tmp", "vagrant-qemu", "vq_invalid")).not_to exist
    end
  end

  it "rejects a TPM device on an unsupported guest architecture" do
    with_temp_dir do |dir|
      driver = VagrantPlugins::QEMU::Driver.new("vq_invalid", dir.join("data"), dir.join("tmp"))
      expect { driver.start(tpm: true, arch: "aarch64") }
        .to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
      expect(dir.join("tmp", "vagrant-qemu", "vq_invalid")).not_to exist
    end
  end

  it "rejects a symlinked state directory without touching its target" do
    skip "POSIX ownership boundary" if Vagrant::Util::Platform.windows?
    with_temp_dir do |dir|
      machine = dir.join("machine")
      target = dir.join("outside")
      runtime = dir.join("runtime")
      sockets = dir.join("sockets")
      [machine, target, runtime, sockets].each { |path| Dir.mkdir(path, 0700) }
      sentinel = target.join("unrelated")
      File.write(sentinel, "retain")
      File.symlink(target, machine.join("tpm"))
      backend = VagrantPlugins::QEMU::Swtpm.new(machine.join("tpm"), runtime, sockets)
      expect { backend.start("swtpm") }.to raise_error(VagrantPlugins::QEMU::Errors::ConfigError)
      expect(File.read(sentinel)).to eq("retain")
      expect(machine.join("tpm").symlink?).to eq(true)
    end
  end
end
