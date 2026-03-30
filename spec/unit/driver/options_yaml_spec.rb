require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "options.yml persistence" do
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

  it "only contains ssh_port and control_port" do
    opt_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(opt_dir)

    persisted = { ssh_port: 50022, control_port: nil }
    File.write(opt_dir.join("options.yml"), persisted.to_yaml)

    loaded = YAML.safe_load_file(opt_dir.join("options.yml"), permitted_classes: [Symbol])
    expect(loaded.keys).to contain_exactly(:ssh_port, :control_port)
  end

  it "can be deserialized by safe_load_file with Symbol" do
    opt_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(opt_dir)

    persisted = { ssh_port: 50023, control_port: 33333 }
    File.write(opt_dir.join("options.yml"), persisted.to_yaml)

    loaded = YAML.safe_load_file(opt_dir.join("options.yml"), permitted_classes: [Symbol])
    expect(loaded[:ssh_port]).to eq 50023
    expect(loaded[:control_port]).to eq 33333
  end

  it "handles control_port=nil correctly" do
    opt_dir = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(opt_dir)

    persisted = { ssh_port: 50022, control_port: nil }
    File.write(opt_dir.join("options.yml"), persisted.to_yaml)

    loaded = YAML.safe_load_file(opt_dir.join("options.yml"), permitted_classes: [Symbol])
    expect(loaded[:control_port]).to be_nil
  end
end
