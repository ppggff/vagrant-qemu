require_relative "helper"

describe "advanced networking end-to-end", :requires_vmnet do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)
      example.run
      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "VM gets the configured static IP" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box_cloudinit}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "private_network", ip: "192.168.105.10"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
          qe.advanced_network = true
          qe.net_mode = :vmnet_shared
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
        config.vm.box = "#{test_box_cloudinit}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "private_network", ip: "192.168.105.11"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
          qe.advanced_network = true
          qe.net_mode = :vmnet_shared
        end
      end
    RUBY

    vagrant_up(@work_dir)
    result = `ping -c 1 -W 5 192.168.105.11 2>&1`
    expect($?.exitstatus).to eq 0
  end

  it "user-specified MAC is applied to the private_network NIC" do
    # NOT 52:54:00:12:34:56 — that's QEMU's default MAC, which would make
    # this test pass even if the mac= argument were dropped entirely.
    user_mac = "52:54:00:aa:bb:cc"
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box_cloudinit}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "private_network", ip: "192.168.105.12", mac: "#{user_mac}"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
          qe.advanced_network = true
          qe.net_mode = :vmnet_shared
        end
      end
    RUBY

    vagrant_up(@work_dir)
    result = vagrant_ssh(@work_dir, command: "ip link show")
    expect(result[:exit_code]).to eq 0
    # `ip link` prints MACs in lowercase with colons; match case-insensitively to be safe.
    expect(result[:stdout].downcase).to include(user_mac.downcase)
  end

  it "two VMs can communicate via private network" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.define "vm1" do |c|
          c.vm.box = "#{test_box_cloudinit}"
          c.vm.box_check_update = false
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.network "private_network", ip: "192.168.105.20"
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.advanced_network = true
            qe.net_mode = :vmnet_shared
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
            qe.net_mode = :vmnet_shared
            qe.ssh_auto_correct = true
          end
        end
      end
    RUBY

    vagrant_up(@work_dir, timeout: 600)

    # VM1 pings VM2 — via the helper (unbundled env) and asserting on the
    # ping output itself, not just an exit code that can pass vacuously.
    result = vagrant_ssh(@work_dir, machine: "vm1", command: "ping -c 1 -W 5 192.168.105.21")
    expect(result[:exit_code]).to eq 0
    expect(result[:stdout]).to include(" 0% packet loss")
  end
end
