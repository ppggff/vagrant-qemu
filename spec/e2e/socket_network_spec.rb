require_relative "helper"

# Advanced networking over the SOCKET (multicast) backend.
#
# Unlike advanced_network_spec.rb (which uses vmnet and is tagged
# :requires_vmnet -> needs sudo), the socket backend needs NO root: QEMU joins
# a UDP multicast group on the host, so two VMs on the same mcast address form
# an L2 segment. This is the only advanced-network backend exercisable on a
# plain machine, and it covers the headline 0.4.0 path end-to-end:
#   build cloud-init seed ISO -> guest cloud-init reads network-config ->
#   static IP applied to the private NIC -> cross-VM traffic over the segment.
#
# Static-IP delivery is backend-independent (the seed is built by the
# CloudInitNetwork action from the private_network ip, regardless of net_mode),
# so a passing socket test also validates the seed-ISO machinery that the
# vmnet test only reaches under root.
#
# Requires an aarch64 cloud-init box (TEST_BOX_CLOUDINIT).
describe "advanced networking over socket multicast (no root)", :requires_qemu do
  # A dedicated multicast group/port so concurrent runs and the QEMU default
  # (230.0.0.1:1234) don't bleed into this segment.
  MCAST = "230.0.0.55:11234".freeze

  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)
      example.run
      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "single VM gets its static IP from the cloud-init seed ISO" do
    # Isolates the seed-ISO path (build + guest reads it) from the multicast
    # plumbing: if the two-VM test below fails, this pinpoints whether IP
    # assignment or cross-VM traffic broke.
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.box = "#{test_box_cloudinit}"
        config.vm.box_check_update = false
        config.vm.synced_folder ".", "/vagrant", disabled: true
        config.vm.network "private_network", ip: "192.168.105.40"
        config.vm.provider "qemu" do |qe|
          qe.memory = "2G"
          qe.advanced_network = true
          qe.net_mode = :socket
          qe.mcast_addr = "#{MCAST}"
        end
      end
    RUBY

    result = vagrant_up(@work_dir, timeout: 600)
    expect(result[:exit_code]).to eq 0

    ssh = vagrant_ssh(@work_dir, command: "ip addr show")
    expect(ssh[:exit_code]).to eq 0
    expect(ssh[:stdout]).to include("192.168.105.40")
  end

  it "two VMs communicate over the socket multicast private network" do
    # QEMU's socket-multicast netdev binds its UDP socket to the multicast
    # group address (net/socket.c net_socket_mcast_create). Darwin's socket
    # stack refuses to send from a socket whose source is a multicast address
    # (sendto -> EADDRNOTAVAIL), so frames never leave the netdev and ARP never
    # resolves -- verified both in a real two-VM run ("Destination Host
    # Unreachable", ARP FAILED) and by replicating the exact socket setup at
    # the syscall level. Both VMs still get their static IP; only VM-to-VM
    # traffic is dead. This is QEMU-vs-Darwin specific, NOT "macOS can't
    # multicast" (an INADDR_ANY bind with loopback egress delivers fine); Linux
    # tolerates the group-address bind, so the socket backend works there. On
    # macOS the VM-to-VM path is vmnet (see advanced_network_spec.rb).
    skip "QEMU socket multicast VM-to-VM not supported on a macOS host" if RbConfig::CONFIG["host_os"] =~ /darwin/

    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        config.vm.define "vm1" do |c|
          c.vm.box = "#{test_box_cloudinit}"
          c.vm.box_check_update = false
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.network "private_network", ip: "192.168.105.41"
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.advanced_network = true
            qe.net_mode = :socket
            qe.mcast_addr = "#{MCAST}"
            qe.ssh_auto_correct = true
          end
        end

        config.vm.define "vm2" do |c|
          c.vm.box = "#{test_box_cloudinit}"
          c.vm.box_check_update = false
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.network "private_network", ip: "192.168.105.42"
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.advanced_network = true
            qe.net_mode = :socket
            qe.mcast_addr = "#{MCAST}"
            qe.ssh_auto_correct = true
          end
        end
      end
    RUBY

    vagrant_up(@work_dir, timeout: 600)

    # From inside vm1, ping vm2 over the socket-backed private NIC. Assert on
    # the ping output itself ("0% packet loss"), not just an exit code that can
    # pass vacuously.
    result = vagrant_ssh(@work_dir, machine: "vm1", command: "ping -c 1 -W 5 192.168.105.42")
    expect(result[:exit_code]).to eq 0
    expect(result[:stdout]).to include(" 0% packet loss")
  end
end

# The :socket backend is just a thin wrapper around QEMU's `socket` netdev:
# the user picks the mode via socket_opts. With a point-to-point TCP
# listen/connect pair (user writes listen= on one VM, connect= on the other)
# there is no multicast, so none of the Darwin EADDRNOTAVAIL problem the mcast
# form hits -- this runs on macOS too and is the real end-to-end proof that the
# no-root VM-to-VM path works.
describe "advanced networking over socket listen/connect (no root)", :requires_qemu do
  STREAM_PORT = 12399

  around(:each) do |example|
    with_temp_dir do |dir|
      @work_dir = dir.join("project")
      FileUtils.mkdir_p(@work_dir)
      example.run
      vagrant_destroy(@work_dir) rescue nil
    end
  end

  it "two VMs communicate over a user-defined listen/connect socket" do
    File.write(@work_dir.join("Vagrantfile"), <<~RUBY)
      Vagrant.configure("2") do |config|
        # The user picks the roles: vm1 listens, vm2 connects. vm1 is defined
        # first so it boots first and is listening before vm2 dials in.
        config.vm.define "vm1" do |c|
          c.vm.box = "#{test_box_cloudinit}"
          c.vm.box_check_update = false
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.network "private_network", ip: "192.168.105.51"
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.advanced_network = true
            qe.net_mode = :socket
            qe.socket_opts = "listen=127.0.0.1:#{STREAM_PORT}"
            qe.ssh_auto_correct = true
          end
        end

        config.vm.define "vm2" do |c|
          c.vm.box = "#{test_box_cloudinit}"
          c.vm.box_check_update = false
          c.vm.synced_folder ".", "/vagrant", disabled: true
          c.vm.network "private_network", ip: "192.168.105.52"
          c.vm.provider "qemu" do |qe|
            qe.memory = "2G"
            qe.advanced_network = true
            qe.net_mode = :socket
            qe.socket_opts = "connect=127.0.0.1:#{STREAM_PORT}"
            qe.ssh_auto_correct = true
          end
        end
      end
    RUBY

    vagrant_up(@work_dir, timeout: 600)

    # vm1 (listener) pings vm2 (connector) over the link. Assert on the ping
    # output itself, not just an exit code that can pass vacuously.
    result = vagrant_ssh(@work_dir, machine: "vm1", command: "ping -c 1 -W 5 192.168.105.52")
    expect(result[:exit_code]).to eq 0
    expect(result[:stdout]).to include(" 0% packet loss")
  end
end
