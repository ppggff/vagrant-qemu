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

  it "two VMs can communicate via private network" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.define "vm1" do |c|
          c.vm.box = "#{test_box_cloudinit}"
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

    # VM1 pings VM2
    result = `cd #{@work_dir} && vagrant ssh vm1 -c "ping -c 1 -W 5 192.168.105.21" 2>/dev/null`
    expect($?.exitstatus).to eq 0
  end
end
