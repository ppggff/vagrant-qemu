require_relative "helper"

describe "cleanup after communicator boot timeout", :requires_qemu do
  it "stops the launched QEMU instance and retains its disks" do
    with_temp_dir do |dir|
      File.write(dir.join("Vagrantfile"), <<~RUBY)
        Vagrant.configure("2") do |config|
          config.vm.box = "#{test_box}"
          config.vm.box_check_update = false
          config.vm.boot_timeout = 10
          config.vm.synced_folder ".", "/vagrant", disabled: true
          config.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.net_device = nil
            qe.ssh_port = 65432
          end
        end
      RUBY

      # No network device means the communicator cannot connect, while the
      # QEMU process still starts. This exercises boot recovery through Warden.
      result = vagrant_up(dir, timeout: 180)
      expect(result[:exit_code]).not_to eq(0), result.inspect
      expect(result[:stderr]).to include("Timed out while waiting for the machine to boot")
      status = vagrant_status(dir)
      expect(status[:exit_code]).to eq(0), status.inspect
      expect(status[:stdout]).to include(",state,stopped")
      expect(dir.glob(".vagrant/machines/default/qemu/*/linked-box.img")).not_to be_empty
    ensure
      vagrant_destroy(dir) rescue nil
    end
  end
end
