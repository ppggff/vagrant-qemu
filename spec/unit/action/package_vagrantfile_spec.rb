require "spec_helper"
require "vagrant-qemu/action/package_vagrantfile"

describe VagrantPlugins::QEMU::Action::PackageVagrantfile do
  let(:app) { lambda { |env| } }
  let(:ui) { double("ui", info: nil) }

  around(:each) do |example|
    with_temp_dir do |dir|
      @export_dir = dir.join("export")
      FileUtils.mkdir_p(@export_dir)
      example.run
    end
  end

  def machine_with(arch)
    c = VagrantPlugins::QEMU::Config.new
    c.arch = arch
    c.finalize!
    double("machine", provider_config: c)
  end

  def run(arch)
    env = { machine: machine_with(arch), ui: ui, "export.temp_dir" => @export_dir.to_s }
    described_class.new(app, env).call(env)
    File.read(@export_dir.join("Vagrantfile"))
  end

  it "writes the VM arch into the default Vagrantfile" do
    expect(run("aarch64")).to include('qe.arch = "aarch64"')
  end

  it "carries a different arch through" do
    expect(run("x86_64")).to include('qe.arch = "x86_64"')
  end

  it "does not bake environment-specific network/MAC/machine config" do
    vf = run("aarch64")
    expect(vf).not_to match(/network|base_mac|accel|machine/i)
  end
end
