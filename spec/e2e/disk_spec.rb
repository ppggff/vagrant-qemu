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
end
