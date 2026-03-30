require_relative "helper"

describe "forwarded ports end-to-end", :requires_qemu do
  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)
      example.run
      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "forwards guest port to host" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "ppggff/centos-7-aarch64-2009-4K"
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "forwarded_port", guest: 8000, host: 18000
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY

    vagrant_up(@work_dir)

    # Start a simple HTTP server in the guest
    vagrant_ssh(@work_dir, command: "nohup python -m SimpleHTTPServer 8000 &>/dev/null &")
    sleep 2

    # Try to connect from host
    result = `curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:18000/ 2>/dev/null`
    expect(result).to eq "200"
  end

  it "ssh_auto_correct allows multiple VMs" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.define "vm1" do |c|
          c.vm.box = "ppggff/centos-7-aarch64-2009-4K"
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.ssh_auto_correct = true
          end
        end

        config.vm.define "vm2" do |c|
          c.vm.box = "ppggff/centos-7-aarch64-2009-4K"
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.ssh_auto_correct = true
          end
        end
      end
    RUBY

    result = vagrant_up(@work_dir, timeout: 600)
    expect(result[:exit_code]).to eq 0

    # Both VMs should be reachable via SSH
    r1 = `cd #{@work_dir} && vagrant ssh vm1 -c "echo ok" 2>/dev/null`.strip
    r2 = `cd #{@work_dir} && vagrant ssh vm2 -c "echo ok" 2>/dev/null`.strip
    expect(r1).to eq "ok"
    expect(r2).to eq "ok"
  end
end
