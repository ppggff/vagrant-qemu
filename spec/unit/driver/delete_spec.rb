require "spec_helper"

describe VagrantPlugins::QEMU::Driver, "#delete" do
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

  it "removes data_dir and tmp_dir when created" do
    id_dir = @data_dir.join(vm_id)
    id_tmp = @tmp_base.join("vagrant-qemu", vm_id)
    FileUtils.mkdir_p(id_dir)
    FileUtils.mkdir_p(id_tmp)

    subject.delete

    expect(id_dir).not_to exist
    expect(id_tmp).not_to exist
  end

  it "does nothing when not created" do
    expect { subject.delete }.not_to raise_error
  end

  it "handles partial directory existence" do
    FileUtils.mkdir_p(@data_dir.join(vm_id))
    # tmp_dir does not exist — should not raise
    expect { subject.delete }.not_to raise_error
  end
end
