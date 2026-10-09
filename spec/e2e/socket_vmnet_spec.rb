require_relative "helper"

# Requires the socket_vmnet daemon running (no sudo for vagrant itself):
#   brew install socket_vmnet && sudo brew services start socket_vmnet
# Run with: TEST_SOCKET_VMNET=1 bundle exec rspec spec/e2e/socket_vmnet_spec.rb
describe "socket_vmnet advanced networking end-to-end", :requires_socket_vmnet do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)
      example.run
      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "VM gets the configured static IP (no sudo)" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        #{snapd_fast_stop}
        config.vm.box = "#{test_box_cloudinit}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "private_network", ip: "192.168.105.10"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
          qe.advanced_network = true
          qe.net_mode = :socket_vmnet
        end
      end
    RUBY

    vagrant_up(@work_dir)
    result = vagrant_ssh(@work_dir, command: "ip addr show")
    expect(result[:stdout]).to include("192.168.105.10")
  end

  it "host can ping the VM IP" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        #{snapd_fast_stop}
        config.vm.box = "#{test_box_cloudinit}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "private_network", ip: "192.168.105.11"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
          qe.advanced_network = true
          qe.net_mode = :socket_vmnet
        end
      end
    RUBY

    vagrant_up(@work_dir)
    `ping -c 1 -t 5 192.168.105.11 2>&1`
    expect($?.exitstatus).to eq 0
  end

  it "two VMs can communicate via the socket_vmnet private network" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        #{snapd_fast_stop}
        config.vm.define "vm1" do |c|
          c.vm.box = "#{test_box_cloudinit}"
          c.vm.box_check_update = false
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.network "private_network", ip: "192.168.105.20"
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.advanced_network = true
            qe.net_mode = :socket_vmnet
            qe.ssh_auto_correct = true
          end
        end

        config.vm.define "vm2" do |c|
          c.vm.box = "#{test_box_cloudinit}"
          c.vm.box_check_update = false
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.network "private_network", ip: "192.168.105.21"
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.advanced_network = true
            qe.net_mode = :socket_vmnet
            qe.ssh_auto_correct = true
          end
        end
      end
    RUBY

    vagrant_up(@work_dir, timeout: 600)
    result = vagrant_ssh(@work_dir, machine: "vm1", command: "ping -c 1 -W 5 192.168.105.21")
    expect(result[:exit_code]).to eq 0
    expect(result[:stdout]).to include(" 0% packet loss")
  end

  # On QEMU >= 7.2 the plugin picks the stream route; a shim that hides the
  # `stream` netdev from the probe forces the wrapper route (socket_vmnet_client
  # + `-netdev socket,fd=3`) so it too gets exercised end-to-end -- in
  # particular that the fd-3 convention survives the plugin's ChildProcess
  # launcher. socket_vmnet_client itself connects on whatever fd `socket()`
  # returns, so this proves nothing extra is leaked into fd 3.
  it "wrapper route (forced via a no-stream shim) connects over fd 3" do
    shim = File.expand_path("support/qemu_no_stream_shim.sh", __dir__)
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        #{snapd_fast_stop}
        config.vm.box = "#{test_box_cloudinit}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "private_network", ip: "192.168.105.13"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
          qe.advanced_network = true
          qe.net_mode = :socket_vmnet
          qe.qemu_bin = "#{shim}"
        end
      end
    RUBY

    vagrant_up(@work_dir)

    # The wrapper route was genuinely taken (not stream): the running QEMU
    # carries the fd-3 socket netdev, not a stream netdev.
    qemu_args = `ps -Ao args 2>/dev/null`
    expect(qemu_args).to include("socket,id=net1,fd=3")
    expect(qemu_args).not_to include("-netdev stream")

    result = vagrant_ssh(@work_dir, command: "ip addr show")
    expect(result[:stdout]).to include("192.168.105.13")
  end
end
