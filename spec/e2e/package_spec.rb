require_relative "helper"

# End-to-end round-trip for `vagrant package`. Exercises the INSTALLED plugin
# (see helper.rb), so rebuild + reinstall before running:
#   bundle exec rake build && vagrant plugin install ./pkg/vagrant-qemu-<ver>.gem
#   TEST_QEMU=1 bundle exec rake spec:e2e
describe "vagrant package end-to-end", :requires_qemu do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      @consume_dir = dir.join("consumer")
      @box_path = dir.join("packaged.box")
      FileUtils.mkdir_p(@work_dir)
      FileUtils.mkdir_p(@consume_dir)
      example.run
      vagrant_destroy(@consume_dir) rescue nil
      vagrant_destroy(@work_dir) rescue nil
      vagrant_box_remove("e2e-packaged", cwd: @work_dir) rescue nil
    end
  end

  def write_source_vagrantfile
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY
  end

  it "packages a running VM into a box that boots again (round-trip)" do
    write_source_vagrantfile
    expect(vagrant_up(@work_dir)[:exit_code]).to eq 0

    result = vagrant_package(@work_dir, output: @box_path)
    expect(result[:exit_code]).to eq 0
    expect(File.exist?(@box_path)).to be true

    # Box layout: box.img + metadata.json + Vagrantfile.
    listing = `tar tzf #{@box_path}`
    expect(listing).to include("box.img")
    expect(listing).to include("metadata.json")
    expect(listing).to include("Vagrantfile")

    # box.img must be a self-contained qcow2 (overlay flattened, no backing).
    Dir.mktmpdir do |ex|
      system("tar xzf #{@box_path} -C #{ex} box.img")
      info = `qemu-img info --output=json #{File.join(ex, "box.img")}`
      expect(info).to include('"format": "qcow2"')
      expect(info).not_to match(/backing-filename/)
    end

    # Consume the packaged box in a fresh project and boot it.
    expect(vagrant_box_add("e2e-packaged", @box_path, cwd: @work_dir)[:exit_code]).to eq 0
    File.write(@consume_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "e2e-packaged"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY
    expect(vagrant_up(@consume_dir)[:exit_code]).to eq 0
    expect(vagrant_ssh(@consume_dir, command: "echo roundtrip-ok")[:stdout]).to include("roundtrip-ok")
  end

  it "does not bake environment-specific network config into the box" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "forwarded_port", guest: 80, host: 8080
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY
    expect(vagrant_up(@work_dir)[:exit_code]).to eq 0
    expect(vagrant_package(@work_dir, output: @box_path)[:exit_code]).to eq 0

    Dir.mktmpdir do |ex|
      system("tar xzf #{@box_path} -C #{ex} Vagrantfile")
      vf = File.read(File.join(ex, "Vagrantfile"))
      expect(vf).to include("qe.arch")
      expect(vf).not_to match(/forwarded_port|network|8080/)
    end
  end
end
