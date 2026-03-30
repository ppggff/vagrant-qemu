require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "#get_ssh_port" do
  let(:vm_id) { "vq_testid123" }

  around(:each) do |example|
    with_temp_dir do |dir|
      @data_dir = dir.join("data")
      @tmp_base = dir.join("tmp")
      FileUtils.mkdir_p(@data_dir)
      FileUtils.mkdir_p(@tmp_base)
      example.run
    end
  end

  subject { described_class.new(vm_id, @data_dir, @tmp_base) }

  it "returns default port when options.yml does not exist" do
    expect(subject.get_ssh_port(50022)).to eq 50022
  end

  it "returns persisted port when options.yml exists" do
    opt_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(opt_dir)
    File.write(opt_dir.join("options.yml"), { ssh_port: 50023 }.to_yaml)

    expect(subject.get_ssh_port(50022)).to eq 50023
  end

  it "returns default port when options.yml is corrupted" do
    opt_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(opt_dir)
    File.write(opt_dir.join("options.yml"), "{{invalid yaml")

    expect(subject.get_ssh_port(50022)).to eq 50022
  end

  it "stores result in @ssh_port" do
    opt_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(opt_dir)
    File.write(opt_dir.join("options.yml"), { ssh_port: 50099 }.to_yaml)

    subject.get_ssh_port(50022)
    expect(subject.ssh_port).to eq 50099
  end
end
