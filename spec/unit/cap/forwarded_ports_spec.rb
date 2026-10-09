require "spec_helper"

describe "QEMU forwarded_ports capability" do
  it "registers the standard capability with Vagrant" do
    expect(VagrantPlugins::QEMU::Plugin.components.provider_capabilities[:qemu].get(:forwarded_ports)).not_to be_nil
  end

  it "returns actual generated host=>guest mappings, including corrected SSH and PSRP" do
    require "vagrant-qemu/cap/forwarded_ports"
    with_temp_dir do |dir|
      FileUtils.mkdir_p(dir.join("vq_ports"))
      File.write(dir.join("vq_ports", "runtime.json"), JSON.generate(argv: ["qemu", "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:61907-:22,hostfwd=tcp:127.0.0.1:61908-:5986", "-name", "hostfwd=tcp:127.0.0.1:1-:2"]))
      driver = double("driver", tmp_dir: dir)
      machine = double("machine", id: "vq_ports", state: double(id: :running), provider: double(driver: driver))
      expect(VagrantPlugins::QEMU::Cap::ForwardedPorts.forwarded_ports(machine)).to eq(61907 => 22, 61908 => 5986)
      File.delete(dir.join("vq_ports", "runtime.json"))
      expect { VagrantPlugins::QEMU::Cap::ForwardedPorts.forwarded_ports(machine) }.to raise_error(Errno::ENOENT)
    end
  end
end
