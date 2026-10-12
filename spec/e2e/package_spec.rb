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
      # The copied consumer Vagrantfile also needs its box name during cleanup,
      # including when the recipe timed out before its own exit trap finished.
      cleanup_env = { "PACKAGE_BOX_NAME" => "e2e-packaged", "TEST_BOX" => test_box }
      [@consume_dir, @work_dir].each do |project|
        run_command("vagrant", "destroy", "-f", cwd: project, timeout: 300,
          env: cleanup_env) rescue nil
      end
      vagrant_box_remove("e2e-packaged", cwd: @work_dir) rescue nil
    end
  end

  it "packages a running VM into a box that boots again (round-trip)" do
    workspace = @work_dir.parent.join("recipe")
    @work_dir = workspace.join("source")
    @consume_dir = workspace.join("consumer")
    @box_path = workspace.join("portable.box")
    recipe = VagrantPlugins::QEMU.source_root.join("examples/package-roundtrip/run.sh")

    result = run_command("bash", recipe.to_s, workspace.to_s,
      cwd: workspace.parent, timeout: 900,
      env: { "TEST_BOX" => test_box, "PACKAGE_BOX_NAME" => "e2e-packaged" })
    expect(result[:exit_code]).to eq(0), "#{result[:stdout]}\n#{result[:stderr]}"
    marker = File.read(workspace.join("verified-marker.txt")).strip
    expect(marker).to match(/\Apackage-roundtrip-[0-9a-f]{32}\z/)
    expect(result[:stdout]).to include("Package round-trip verified: #{marker}")
    expect(@box_path).to be_file
  end

  it "does not bake environment-specific network config into the box" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "forwarded_port", guest: 80, host: 8080, auto_correct: true
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY
    expect(vagrant_up(@work_dir)[:exit_code]).to eq 0
    expect(vagrant_package(@work_dir, output: @box_path)[:exit_code]).to eq 0

    Dir.mktmpdir do |ex|
      system("tar xzf #{@box_path} -C #{ex}")
      vf = File.read(File.join(ex, "Vagrantfile"))
      expect(vf).to include("qe.arch")
      expect(vf).not_to match(/forwarded_port|network|8080/)
    end
  end
end
