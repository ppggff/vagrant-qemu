require_relative "helper"
require "json"

describe "VirtioFS folder lifecycle", :requires_virtiofs do
  around do |example|
    with_temp_dir do |dir|
      @project = dir.join("project")
      FileUtils.mkdir_p(@project.join("first share"))
      FileUtils.mkdir_p(@project.join("second share"))
      File.write(@project.join("first share/from-host"), "HOST_PAYLOAD_A_73f9\n")
      File.write(@project.join("second share/from-host"), "HOST_PAYLOAD_B_92c1\n")
      File.write(@project.join("Vagrantfile"), <<~RUBY)
        Vagrant.configure("2") do |config|
          config.vm.box = #{ENV.fetch("TEST_BOX", "cloud-image/debian-12").inspect}
          config.vm.box_check_update = false
          config.vm.boot_timeout = 600
          config.vm.allowed_synced_folder_types = [:qemu_virtiofs]
          config.vm.synced_folder ".", "/vagrant", disabled: true
          # Leave the first type implicit to exercise Vagrant's resolved mapping.
          config.vm.synced_folder "first share", "/mnt/first share"
          config.vm.synced_folder "second share", "/mnt/second", type: "qemu_virtiofs"
          config.vm.provider "qemu" do |qe|
            qe.memory = "1.3G"
            qe.ssh_port = 50222
            if RUBY_PLATFORM.include?("darwin")
              qe.cpu = "max"
              qe.machine = "virt,highmem=on,accel=tcg"
            end
          end
        end
      RUBY
      begin
        example.run
      ensure
        vagrant_destroy(@project) rescue nil
      end
    end
  end

  def successful(result)
    puts result[:stdout]
    puts result[:stderr] unless result[:stderr].empty?
    expect(result[:exit_code]).to eq(0), result.inspect
    result
  end

  def daemons
    Dir.glob(@project.join(".vagrant/machines/default/qemu/virtiofs/*.pid")).map do |file|
      { pid: File.read(file).to_i, socket: File.read(file.sub(/\.pid$/, ".sock_path")).strip }
    end
  end

  def expect_daemons_stopped(records, sockets_removed: true)
    records.each do |record|
      # Allow the host init process to reap a daemon killed during shutdown.
      20.times do
        begin
          Process.kill(0, record[:pid])
          sleep 0.1
        rescue Errno::ESRCH
          break
        end
      end
      expect { Process.kill(0, record[:pid]) }.to raise_error(Errno::ESRCH)
      expect(File.exist?(record[:socket])).to eq(false) if sockets_removed
    end
  end

  def verify_shares
    result = successful(vagrant_ssh(@project, command: "mount | grep virtiofs && cat '/mnt/first share/from-host' && cat /mnt/second/from-host"))
    expect(result[:stdout]).to include("virtiofs0 on /mnt/first share type virtiofs", "virtiofs1 on /mnt/second type virtiofs",
      "HOST_PAYLOAD_A_73f9", "HOST_PAYLOAD_B_92c1")
    successful(vagrant_ssh(@project, command: "sudo sh -c 'echo guest-first > \"/mnt/first share/from-guest\"; echo guest-second > /mnt/second/from-guest'"))
    expect(File.read(@project.join("first share/from-guest")).strip).to eq("guest-first")
    expect(File.read(@project.join("second share/from-guest")).strip).to eq("guest-second")
  end

  it "mounts resolved shares, survives reload, and stops daemons on halt and destroy" do
    successful(vagrant_up(@project, timeout: 600))
    verify_shares
    # Removing a host payload must fail the same SSH command used above.
    # Mount output alone must never count as proof of host-to-guest reads.
    File.rename(@project.join("first share/from-host"), @project.join("first share/hidden"))
    missing = vagrant_ssh(@project, command: "mount | grep virtiofs && cat '/mnt/first share/from-host' && cat /mnt/second/from-host")
    expect(missing[:exit_code]).not_to eq(0)
    File.rename(@project.join("first share/hidden"), @project.join("first share/from-host"))
    running = daemons
    expect(running.length).to eq(2)

    successful(vagrant_reload(@project, timeout: 900))
    # Reload starts new listeners at the same socket paths; old PIDs must die.
    expect_daemons_stopped(running, sockets_removed: false)
    verify_shares
    running = daemons

    successful(vagrant_halt(@project))
    expect_daemons_stopped(running)
    successful(vagrant_up(@project, timeout: 600))
    verify_shares
    running = daemons
    expect(running.length).to eq(2)

    successful(vagrant_destroy(@project))
    expect_daemons_stopped(running)
    expect(@project.join(".vagrant/machines/default/qemu/virtiofs")).not_to exist
  end
end
