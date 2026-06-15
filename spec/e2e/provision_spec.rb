require_relative "helper"

describe "shell provisioner end-to-end", :requires_qemu do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)
      example.run
      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "inline shell provisioner runs and creates a marker file" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box}"
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
        config.vm.provision "shell", inline: "echo provisioned > /tmp/vagrant-qemu-marker"
      end
    RUBY

    result = vagrant_up(@work_dir, timeout: 600)
    expect(result[:exit_code]).to eq 0

    ssh = vagrant_ssh(@work_dir, command: "cat /tmp/vagrant-qemu-marker")
    expect(ssh[:exit_code]).to eq 0
    # `vagrant ssh` may prepend a banner (e.g. "running outside of official installers").
    # Match the last line, which is the actual remote command output.
    expect(ssh[:stdout].lines.last.to_s.strip).to eq "provisioned"
  end
end
