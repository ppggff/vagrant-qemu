require_relative "helper"

describe "halt and destroy (mock QEMU)", :acceptance do
  around(:each) do |example|
    with_temp_dir do |dir|
      @dir = dir
      @bin_dir = create_fake_qemu(dir)
      example.run
    end
  end

  it "force_kill terminates a background process" do
    pid_file = @dir.join("test.pid")
    system("#{@bin_dir.join('qemu-system-aarch64')} -pidfile #{pid_file} -daemonize")
    sleep 0.5

    pid = File.read(pid_file).to_i
    Process.kill("KILL", pid)
    sleep 0.1

    alive = begin
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
    expect(alive).to eq false
  end

  it "Driver#delete removes data and tmp directories" do
    data_dir = @dir.join("data")
    tmp_base = @dir.join("tmp")
    vm_id = "vq_test_halt"

    FileUtils.mkdir_p(data_dir.join(vm_id))
    FileUtils.mkdir_p(tmp_base.join("vagrant-qemu", vm_id))

    driver = VagrantPlugins::QEMU::Driver.new(vm_id, data_dir, tmp_base)
    driver.delete

    expect(data_dir.join(vm_id)).not_to exist
    expect(tmp_base.join("vagrant-qemu", vm_id)).not_to exist
  end

  it "Driver#delete on not_created does not raise" do
    data_dir = @dir.join("data")
    tmp_base = @dir.join("tmp")
    FileUtils.mkdir_p(data_dir)
    FileUtils.mkdir_p(tmp_base)

    driver = VagrantPlugins::QEMU::Driver.new("vq_nonexistent", data_dir, tmp_base)
    expect { driver.delete }.not_to raise_error
  end

  it "Driver#get_current_state returns :not_created after delete" do
    data_dir = @dir.join("data")
    tmp_base = @dir.join("tmp")
    vm_id = "vq_test_state"

    FileUtils.mkdir_p(data_dir.join(vm_id))
    FileUtils.mkdir_p(tmp_base)

    driver = VagrantPlugins::QEMU::Driver.new(vm_id, data_dir, tmp_base)
    expect(driver.get_current_state).to eq :stopped

    driver.delete
    expect(driver.get_current_state).to eq :not_created
  end
end
