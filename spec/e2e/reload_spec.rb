require_relative "helper"

describe "reload and state persistence", :requires_qemu do
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

      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "vagrant reload halts and starts the VM" do
    vagrant_up(@work_dir)

    result = vagrant_reload(@work_dir, timeout: 600)
    expect(result[:exit_code]).to eq 0

    status = vagrant_status(@work_dir)
    expect(status[:stdout]).to include(",state,running")

    ssh = vagrant_ssh(@work_dir, command: "echo ok")
    expect(ssh[:exit_code]).to eq 0
    expect(ssh[:stdout].strip).to include("ok")
  end

  it "halt then vagrant up resumes the VM" do
    vagrant_up(@work_dir)

    halt = vagrant_halt(@work_dir)
    expect(halt[:exit_code]).to eq 0

    status_after_halt = vagrant_status(@work_dir)
    # Positive assertion on the machine-readable state line — a negative
    # match can pass vacuously (",running," never appears in any state).
    expect(status_after_halt[:stdout]).to include(",state,stopped")

    up_again = vagrant_up(@work_dir)
    expect(up_again[:exit_code]).to eq 0

    ssh = vagrant_ssh(@work_dir, command: "hostname")
    expect(ssh[:exit_code]).to eq 0
    expect(ssh[:stdout].strip).not_to be_empty
  end
end
