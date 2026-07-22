require_relative "helper"

describe "extra disk attachment end-to-end", :requires_qemu do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)
      example.run
      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "extra qcow2 disk is visible inside the guest" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.disk :disk, name: "extra", size: "1GB"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY

    result = vagrant_up(@work_dir, timeout: 600)
    expect(result[:exit_code]).to eq 0

    # Count physical disks visible to the guest. Boot disk + 1 extra = 2.
    # Last line is the count; earlier lines may contain a `vagrant ssh` banner.
    ssh = vagrant_ssh(@work_dir, command: %q{lsblk -d -n -o TYPE | grep -c '^disk$'})
    expect(ssh[:exit_code]).to eq 0
    expect(ssh[:stdout].lines.last.to_s.strip.to_i).to be >= 2
  end

  it "reload with an extra disk does not hit a QEMU image-lock error" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.disk :disk, name: "extra", size: "1GB"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY

    result = vagrant_up(@work_dir, timeout: 600)
    expect(result[:exit_code]).to eq 0

    # This is the exact same-process halt->start path a same-process reload
    # takes (issue #41: reload used to re-attach the extra disk a second
    # time, so QEMU refused its own duplicate -drive with a write-lock error).
    reload = vagrant_reload(@work_dir, timeout: 600)
    expect(reload[:exit_code]).to eq 0
    expect(reload[:stderr]).not_to match(/Failed to get "write" lock/)

    ssh = vagrant_ssh(@work_dir, command: %q{lsblk -d -n -o TYPE | grep -c '^disk$'})
    expect(ssh[:exit_code]).to eq 0
    expect(ssh[:stdout].lines.last.to_s.strip.to_i).to be >= 2
  end

  it "reload does not wipe data already written to an extra disk" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.disk :disk, name: "extra", size: "1GB"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY

    result = vagrant_up(@work_dir, timeout: 600)
    expect(result[:exit_code]).to eq 0

    setup = vagrant_ssh(@work_dir, command: <<~SH)
      set -e
      dev=$(lsblk -d -n -o NAME,TYPE | awk '$2=="disk"{print $1}' | grep -v vda | head -1)
      sudo mkfs.ext4 -F /dev/$dev
      sudo mkdir -p /mnt/extra
      sudo mount /dev/$dev /mnt/extra
      echo marker-should-survive-reload | sudo tee /mnt/extra/marker.txt
      sudo umount /mnt/extra
    SH
    expect(setup[:exit_code]).to eq 0

    # configure_disks unconditionally ran `qemu-img create` on every
    # action_start (including this same-process reload), silently
    # truncating the extra disk every time -- this is the regression test.
    reload = vagrant_reload(@work_dir, timeout: 600)
    expect(reload[:exit_code]).to eq 0

    check = vagrant_ssh(@work_dir, command: <<~SH)
      set -e
      dev=$(lsblk -d -n -o NAME,TYPE | awk '$2=="disk"{print $1}' | grep -v vda | head -1)
      sudo mkdir -p /mnt/extra
      sudo mount /dev/$dev /mnt/extra
      cat /mnt/extra/marker.txt
    SH
    expect(check[:exit_code]).to eq 0
    expect(check[:stdout]).to include("marker-should-survive-reload")
  end
end
