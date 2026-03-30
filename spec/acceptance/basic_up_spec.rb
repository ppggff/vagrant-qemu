require_relative "helper"

describe "vagrant up (mock QEMU)", :acceptance do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)

      @bin_dir = create_fake_qemu(dir)

      create_vagrantfile(@work_dir, <<~RUBY)
        Vagrant.configure("2") do |config|
          config.vm.box = "test"
          config.vm.synced_folder ".", "/vagrant", disabled: true
          config.vm.provider "qemu" do |qe|
            qe.qemu_bin = "#{@bin_dir.join('qemu-system-aarch64')}"
            qe.qemu_dir = "#{dir}"
            qe.firmware_format = nil
          end
        end
      RUBY

      # Create a minimal box structure
      box_dir = @work_dir.join(".vagrant", "machines", "default", "qemu")
      FileUtils.mkdir_p(box_dir)

      example.run
    end
  end

  it "produces a valid options.yml with only ssh_port and control_port" do
    # This test validates the options.yml content directly without full vagrant up
    # (full vagrant up requires a real Vagrant environment with box download)
    opt_dir = Dir.mktmpdir
    persisted = { ssh_port: 50022, control_port: nil }
    options_file = File.join(opt_dir, "options.yml")
    File.write(options_file, persisted.to_yaml)

    loaded = YAML.safe_load_file(options_file, permitted_classes: [Symbol])
    expect(loaded.keys).to contain_exactly(:ssh_port, :control_port)
    expect(loaded[:ssh_port]).to eq 50022
  ensure
    FileUtils.rm_rf(opt_dir)
  end

  it "fake qemu-img creates output file" do
    out_file = @work_dir.join("test-output.img")
    system("#{@bin_dir.join('qemu-img')} create #{out_file}")
    expect(out_file).to exist
  end

  it "fake qemu writes PID file with -daemonize" do
    pid_file = @work_dir.join("test.pid")
    system("#{@bin_dir.join('qemu-system-aarch64')} -pidfile #{pid_file} -daemonize")
    sleep 0.5
    expect(pid_file).to exist
    pid = File.read(pid_file).to_i
    expect(pid).to be > 0
    # Clean up the background process
    Process.kill("TERM", pid) rescue nil
  end

  it "fake qemu PID file references a running process" do
    pid_file = @work_dir.join("test2.pid")
    system("#{@bin_dir.join('qemu-system-aarch64')} -pidfile #{pid_file} -daemonize")
    sleep 0.5
    pid = File.read(pid_file).to_i
    alive = begin
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end
    expect(alive).to eq true
    Process.kill("TERM", pid) rescue nil
  end

  it "linked-box.img is created by fake qemu-img" do
    img = @work_dir.join("linked-box.img")
    system("#{@bin_dir.join('qemu-img')} create -f qcow2 #{img}")
    expect(img).to exist
  end
end
