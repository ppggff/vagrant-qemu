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
        config.vm.box = "#{test_box}"
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "forwarded_port", guest: 8000, host: 18000
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
        end
      end
    RUBY

    vagrant_up(@work_dir)

    # Verify port forwarding by checking that the forwarded port is listening on the host.
    # The SSH port forwarding (hostfwd) is set up by QEMU at start time,
    # so port 18000 should be forwarded even without a service on guest:8000.
    # We verify by checking that a TCP connection to the host port is accepted
    # (QEMU's user-mode networking accepts and forwards the connection).
    require 'socket'
    connected = false
    begin
      sock = TCPSocket.new("127.0.0.1", 18000)
      connected = true
      sock.close
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
      connected = false
    end
    expect(connected).to eq true
  end

  it "user-defined forwarded_port auto-corrects when host port is in use" do
    require 'socket'
    # Hold the host port in this process so QEMU's hostfwd attempt would collide.
    blocker = TCPServer.new("127.0.0.1", 28000)
    begin
      File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
        Vagrant.configure("2") do |config|
          config.vm.box = "#{test_box}"
          config.vm.synced_folder ".", "/vagrant", disabled: true
          config.vm.network "forwarded_port", guest: 80, host: 28000, auto_correct: true
          config.vm.provider "qemu" do |qe|
            qe.memory = "2G"
          end
        end
      RUBY

      # Without auto-correct, QEMU's hostfwd would fail to bind 28000 and `up` would error.
      # Successful `up` proves Vagrant remapped the host port.
      result = vagrant_up(@work_dir, timeout: 300)
      expect(result[:exit_code]).to eq 0
    ensure
      blocker.close rescue nil
    end
  end

  it "ssh_auto_correct allows multiple VMs" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.define "vm1" do |c|
          c.vm.box = "#{test_box}"
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.ssh_auto_correct = true
          end
        end

        config.vm.define "vm2" do |c|
          c.vm.box = "#{test_box}"
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
    # Use vagrant_ssh helper which captures only the command output
    r1 = vagrant_ssh(@work_dir.to_s, command: "echo ok")
    r2_result = `cd #{@work_dir} && VAGRANT_CWD=#{@work_dir} vagrant ssh vm1 -c "echo ok" 2>&1`
    r2_result2 = `cd #{@work_dir} && VAGRANT_CWD=#{@work_dir} vagrant ssh vm2 -c "echo ok" 2>&1`
    expect(r2_result.lines.last.strip).to eq "ok"
    expect(r2_result2.lines.last.strip).to eq "ok"
  end
end
