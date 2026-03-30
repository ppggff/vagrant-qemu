require_relative "helper"

describe "smoke test: full VM lifecycle", :requires_qemu do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)

      File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
        Vagrant.configure("2") do |config|
          config.vm.box = "#{test_box}"
          config.vm.synced_folder ".", "/vagrant", disabled: true
          config.vm.provider "qemu" do |qe|
            qe.memory = "2G"
          end
        end
      RUBY

      example.run

      # Always try to destroy after test
      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "vagrant up brings VM to running state" do
    result = vagrant_up(@work_dir)
    expect(result[:exit_code]).to eq 0

    status = vagrant_status(@work_dir)
    expect(status[:stdout]).to include("running")
  end

  it "vagrant ssh can execute a command" do
    vagrant_up(@work_dir)
    result = vagrant_ssh(@work_dir, command: "hostname")
    expect(result[:exit_code]).to eq 0
    expect(result[:stdout].strip).not_to be_empty
  end

  it "vagrant halt stops the VM" do
    vagrant_up(@work_dir)
    result = vagrant_halt(@work_dir)
    expect(result[:exit_code]).to eq 0

    status = vagrant_status(@work_dir)
    # Should not be running
    expect(status[:stdout]).not_to include(",running,")
  end

  it "vagrant destroy removes the VM" do
    vagrant_up(@work_dir)
    result = vagrant_destroy(@work_dir)
    expect(result[:exit_code]).to eq 0

    status = vagrant_status(@work_dir)
    expect(status[:stdout]).to include("not_created")
  end
end
