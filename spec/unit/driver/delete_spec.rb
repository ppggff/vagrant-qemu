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

  it "removes sockets recorded under another VAGRANT_HOME and their emptied directory" do
    other = @tmp_base.dirname.join("other-home", "tmp", "vagrant-qemu", vm_id)
    FileUtils.mkdir_p(other)
    sockets = [other.join("qemu_socket"), other.join("qemu_socket_serial")]
    sockets.each { |f| FileUtils.touch(f) }
    run_dir = @data_dir.join(vm_id, "run")
    FileUtils.mkdir_p(run_dir)
    File.write(run_dir.join("options.yml"),
               { monitor_socket: sockets[0].to_s, serial_socket: sockets[1].to_s }.to_yaml)

    subject.delete

    expect(other).not_to exist
    expect(other.dirname).to exist
  end

  it "keeps a recorded socket's directory when other files remain in it" do
    other = @tmp_base.dirname.join("other-home", "tmp", "vagrant-qemu", vm_id)
    FileUtils.mkdir_p(other)
    FileUtils.touch(other.join("qemu_socket"))
    FileUtils.touch(other.join("unrelated"))
    run_dir = @data_dir.join(vm_id, "run")
    FileUtils.mkdir_p(run_dir)
    File.write(run_dir.join("options.yml"), { monitor_socket: other.join("qemu_socket").to_s }.to_yaml)

    subject.delete

    expect(other.join("qemu_socket")).not_to exist
    expect(other.join("unrelated")).to exist
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
