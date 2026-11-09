require_relative "helper"
require "json"

# Regression for #96: the provider must keep finding and stopping a running
# VM when its runtime directory under VAGRANT_HOME's tmp dir is gone, or when
# a later command runs under another VAGRANT_HOME.
describe "a running VM stays manageable without its tmp runtime dir (#96)", :requires_qemu do
  around(:each) do |example|
    with_temp_dir do |dir|
      @dir = dir
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)

      File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
        Vagrant.configure("2") do |config|
          config.vm.box = "#{test_box}"
          config.vm.box_check_update = false
          config.vm.synced_folder ".", "/vagrant", disabled: true
          config.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.graceful_timeout = 30
          end
        end
      RUBY

      example.run

      vagrant_destroy(@work_dir) rescue nil
    end
  end

  def vm_id
    File.read(@work_dir.join(".vagrant", "machines", "default", "qemu", "id")).strip
  end

  def qemu_pid
    File.read(@work_dir.join(".vagrant", "machines", "default", "qemu", vm_id, "run", "qemu.pid")).to_i
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def home_tmp_runtime_dir
    home = ENV["VAGRANT_HOME"] || File.join(Dir.home, ".vagrant.d")
    Pathname.new(home).join("tmp", "vagrant-qemu", vm_id)
  end

  def run_under_home(home, *args, timeout: 120)
    send(:run_command, "vagrant", *args, cwd: @work_dir, timeout: timeout, env: { "VAGRANT_HOME" => home.to_s })
  end

  it "reports running and halts with SIGTERM after the tmp runtime dir is deleted" do
    result = vagrant_up(@work_dir)
    expect(result[:exit_code]).to eq(0), result.inspect
    pid = qemu_pid

    FileUtils.rm_rf(home_tmp_runtime_dir)

    expect(vagrant_status(@work_dir)[:stdout]).to include(",state,running")
    ssh = vagrant_ssh(@work_dir, command: "echo ok")
    expect(ssh[:stdout]).to include("ok"), ssh.inspect

    halt = vagrant_halt(@work_dir, timeout: 60, debug: true)
    expect(halt[:exit_code]).to eq(0), halt.inspect
    logs = halt[:stdout] + halt[:stderr]
    expect(logs).to include("monitor unreachable; sending SIGTERM")
    expect(logs).not_to include("forcing kill")
    expect(alive?(pid)).to eq false
    expect(vagrant_status(@work_dir)[:stdout]).to include(",state,stopped")
  end

  it "is found, described, halted and destroyed from another VAGRANT_HOME" do
    result = vagrant_up(@work_dir)
    expect(result[:exit_code]).to eq(0), result.inspect
    pid = qemu_pid
    serial_socket = home_tmp_runtime_dir.join("qemu_socket_serial").to_s

    other_home = @dir.join("other-home")
    gem = File.expand_path("../../pkg/vagrant-qemu-#{VagrantPlugins::QEMU::VERSION}.gem", __dir__)
    expect(File.exist?(gem)).to eq(true), "build the gem first: #{gem}"
    install = run_under_home(other_home, "plugin", "install", gem, timeout: 300)
    expect(install[:exit_code]).to eq(0), install.inspect

    status = run_under_home(other_home, "status", "--machine-readable")
    expect(status[:stdout]).to include(",state,running"), status.inspect

    ssh = run_under_home(other_home, "ssh", "-c", "echo ok", timeout: 60)
    expect(ssh[:stdout]).to include("ok"), ssh.inspect

    serial = run_under_home(other_home, "serial-config", "--json")
    expect(JSON.parse(serial[:stdout]).first["endpoint"]).to include("path" => serial_socket), serial.inspect

    halt = run_under_home(other_home, "halt", "--debug", timeout: 90)
    expect(halt[:exit_code]).to eq(0), halt.inspect
    logs = halt[:stdout] + halt[:stderr]
    expect(logs).not_to include("monitor unreachable")
    expect(alive?(pid)).to eq false

    id = vm_id
    tmp_dir = home_tmp_runtime_dir
    destroy = run_under_home(other_home, "destroy", "-f", timeout: 120)
    expect(destroy[:exit_code]).to eq(0), destroy.inspect
    expect(@work_dir.join(".vagrant", "machines", "default", "qemu", id)).not_to exist
    expect(tmp_dir).not_to exist
  end
end
