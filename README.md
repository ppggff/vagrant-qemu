# Vagrant QEMU Provider

This is a Vagrant plugin that adds a simple QEMU provider to Vagrant, allowing Vagrant
to control and provision machines using QEMU.

**Notes: test with Apple Silicon / M1 and CentOS / Ubuntu aarch64 image**

## Compatible with

Tested:

* MacOS >= 12.4
* QEMU >= 7.0.0
* CentOS (centos-7-aarch64-2009-4K)
* Ubuntu (see [Wiki](https://github.com/ppggff/vagrant-qemu/wiki) for detais)
* Debian buster64 on x86_64 (see [Wiki](https://github.com/ppggff/vagrant-qemu/wiki) for detais)

Others:

* (MacOS < 12.4) + (QEMU >= 7.0.0) : update OS, or use QEMU 6.x
* QEMU 6.x: use following config:
  ```
  config.vm.provider "qemu" do |qe|
    qe.machine = "virt,accel=hvf,highmem=off"
    qe.cpu = "cortex-a72"
  end
  ```

## Features

* Import from a Libvirt vagrant box or qcow2 image
  * To use box for **Paralles or VMware Fusion**, see [Wiki](https://github.com/ppggff/vagrant-qemu/wiki) for details
  * Libvirt box v2 format support is experimental
* Start VM without GUI
* SSH into VM
* Provision the instances with any built-in Vagrant provisioner
* Synced folder support via SMB
* Basic operation: up, ssh, halt, destroy
* Basic suport to forwarded ports, see [vagrant doc](https://www.vagrantup.com/docs/networking/forwarded_ports) for details
* Support Cloud-init, see [vagrant doc](https://developer.hashicorp.com/vagrant/docs/cloud-init/usage) for details
* Support Disks, see [vagrant doc](https://developer.hashicorp.com/vagrant/docs/disks/usage) for details
* Advanced networking (opt-in): dual-NIC with `private_network` support via QEMU native vmnet (macOS), TAP (Linux), or a `socket` netdev — multicast (Linux/Windows) or point-to-point listen/connect (no root, works on macOS)

## Usage

Make sure QEMU is installed, if not:

```
brew install qemu
```

Install plugin:

```
vagrant plugin install vagrant-qemu
```

Prepare a `Vagrantfile`, see [Example](#example), and start:

```
vagrant up --provider qemu
```

Notes:
* may need password to setup SMB on Mac,
  see [vagrant doc](https://www.vagrantup.com/docs/synced-folders/smb) for details
* need username/password to access shared folder

## Box format

Same as [vagrant-libvirt version-1](https://github.com/vagrant-libvirt/vagrant-libvirt#version-1):

* qcow2 image file named `box.img`
* `metadata.json` file describing box image (provider, virtual_size, format)
* `Vagrantfile` that does default settings

## Configuration

### Options

This provider exposes a few provider-specific configuration options:

* basic
  * `ssh_port` - The SSH port number used to access VM, default: `50022`
  * `arch` - The architecture of VM, default: auto-detected from the host (`aarch64` on Apple Silicon, `x86_64` on Intel)
  * `machine` - The machine type of VM, default: auto-detected from host OS + arch. For native virtualization (guest arch == host arch): `virt,highmem=on,accel=hvf` (arm64) / `q35,accel=hvf` (x86_64) on macOS, `accel=kvm` on Linux, `accel=whpx` on Windows. When emulating a non-host arch it uses `accel=tcg`.
  * `cpu` - The cpu model of VM, default: `host` for native virtualization, `max` when emulating a non-host arch
  * `smp` - The smp setting (Simulate an SMP system with n CPUs) of VM, default: `2`
  * `memory` - The memory setting of VM, default: `4G`
  * `disk_resize` - The target disk size of the primary disk, requires resizing of filesystem inside of VM, default: `nil`.
* debug/expert
  * `ssh_host` - The SSH IP used to access VM, default: `127.0.0.1`
  * `ssh_auto_correct` - Auto correct port collisions for ssh port, default: `false`
  * `net_device` - The network device, default: auto-detected — `virtio-net-device` (arm64 `virt`) or `virtio-net-pci` (x86_64 `q35`)
  * `drive_interface` - The interface type for the main drive, default `virtio`
  * `image_path` - The path (or array of paths) to qcow2 image for box-less VM, default is nil value
  * `qemu_bin` - Path to an alternative QEMU binary, default: autodetected
  * `qemu_dir` - The path to QEMU's data/firmware dir. Default resolution order: `ENV["QEMU_DIR"]` → `${HOMEBREW_PREFIX}/share/qemu` → per-host default (`/opt/homebrew/share/qemu` on Apple Silicon, `/usr/local/share/qemu` on Intel macOS, `/usr/share/qemu` on Linux). Only consumed for aarch64 firmware; ignored (and not validated) for x86_64.
  * `extra_qemu_args` - The raw list of additional arguments to pass to QEMU. Use with extreme caution. (see "Force Multicore" below as example)
  * `extra_netdev_args` - extra, comma-separated arguments to pass to the -netdev parameter. Use with caution. (see "Force Local IP" below as example)
  * `extra_drive_args` - Add optional extra arguments to each drive attached, default: `[]`
  * `control_port` - The port number used to control vm from vagrant, default is nil value. (nil means use unix socket)
  * `debug_port` - The port number used to export serial port of the vm for debug, default is nil value. (nil means use unix socket, see "Debug" below for details)
  * `no_daemonize` - Disable the "daemonize" mode of QEMU, default is false. (see "Windows host" below as example)
  * `firmware_format` - The format of aarch64 firmware images (`edk2-aarch64-code.fd` and `edk2-arm-vars.fd`) loaded from `qemu_dir`, default: `raw`
  * `other_default` - The other default arguments used by this plugin, default: `%W(-parallel null -monitor none -display none -vga none)`
  * `extra_image_opts` - Options passed via `-o` to `qemu-img` when the base qcow2 images are created, default: `[]`
  * `graceful_timeout` - Seconds to wait at each `vagrant halt` stage before escalating, default: `60`. Halt sends ACPI `system_powerdown`, waits up to this long, then sends QEMU's `quit` monitor command (a clean shutdown that flushes and closes the disk images), waits again, and finally SIGKILLs QEMU as a last resort — so halt still completes even when the guest was already halted from inside (e.g. `sudo systemctl halt`), where `system_powerdown` is a no-op
* advanced networking (requires `advanced_network = true`)
  * `advanced_network` - Enable dual-NIC advanced networking with `private_network` support, default: `false`
  * `net_mode` - Network backend: `:auto` (detect by platform), `:vmnet_shared`, `:vmnet_host`, `:vmnet_bridged` (macOS), `:tap` (Linux), `:socket` (QEMU `socket` netdev — multicast or point-to-point, see `socket_opts`), default: `:auto`
  * `vmnet_interface` - Physical interface for vmnet-bridged mode, default: `en0`
  * `tap_device` - TAP device name for Linux tap backend, default: `nil` (uses `tap0`)
  * `mcast_addr` - Convenience shortcut for the `:socket` backend's multicast address, default: `nil` (uses `230.0.0.1:1234`)
  * `socket_opts` - Raw options for the `:socket` netdev, emitted verbatim as `-netdev socket,id=netN,<socket_opts>`. You pick the mode: `"mcast=230.0.0.1:1234"` (multicast, N-way), `"listen=:1234"` / `"connect=127.0.0.1:1234"` (point-to-point; you decide which VM listens and which connects — the no-root, macOS-friendly path). Overrides `mcast_addr`. Default: `nil` (falls back to multicast)

### Usage

These can be set like typical provider-specific configuration:

```
# Basic Vagrant config (API version 2)
Vagrant.configure(2) do |config|
  # ... other stuff

  config.vm.provider "qemu" do |qe|
    qe.memory = "8G"
  end
end
```

### With `nil` value

To be able to custom the result qemu command deeply, you can set some config options
to `nil` value to skip related qemu arguments.

* `machine`: skip `-machine xxx`
* `cpu`: skip `-cpu xxx`
* `smp`: skip `-smp xxx`
* `memory`: skip `-m xxx`
* `net_device`: skip all network related arguments:
  * `-device xxx,netdev=net0`
  * `-netdev user,id=net0,xxx`
  * NOTES: there will be no network, ssh won't work
* `drive_interface`: skip drive for the main image, `-drive if=xxx,xxx`
* `firmware_format`: skip firmware setup for aarch64, `-drive if=pflash,xxx`

With `other_default = []`, all default arguments will be skipped.

## Example

1. Try with a sample box

```
vagrant init ppggff/centos-7-aarch64-2009-4K
vagrant up --provider qemu
```

2. With a local box

```
# Basic Vagrant config (API version 2)
Vagrant.configure(2) do |config|
  config.vm.box = "test-box"
  config.vm.box_url = "file:///Users/xxx/test.box"
  config.vm.box_check_update = false
end
```

3. With a local qcow2

```
# Basic Vagrant config (API version 2)
Vagrant.configure(2) do |config|
  config.vm.provider "qemu" do |qe, override|
    override.ssh.username = "xxx"
    override.ssh.password = "vagrant"

    qe.image_path = "/Users/xxx/test.qcow2"
  end
end
```

4. Work with a x86_64 box (basic config)

On an **Intel Mac** (or Linux x86_64 host) these defaults are now auto-detected,
so a plain `config.vm.box = "..."` with no provider overrides is usually enough.
The explicit settings below are only needed to **emulate** x86_64 on an Apple
Silicon host (cross-arch → TCG):

```
Vagrant.configure(2) do |config|
  config.vm.box = "centos/7"

  config.vm.provider "qemu" do |qe|
    qe.arch = "x86_64"
    qe.machine = "q35"
    qe.cpu = "qemu64"
    qe.net_device = "virtio-net-pci"
  end
end
```

5. Forwarded ports

```
# Basic Vagrant config (API version 2)
Vagrant.configure(2) do |config|
  # ... other stuff

  config.vm.network "forwarded_port", guest: 80, host: 8080
end
```

6. Force Multicore (x86)

Thanks to [taraszka](https://github.com/taraszka) for providing this config.

```
Vagrant.configure("2") do |config|
  config.vm.box = "centos/7"

  config.vm.provider "qemu" do |qe|
    qe.arch = "x86_64"
    qe.machine = "q35"
    qe.cpu = "max"
    qe.smp = "cpus=2,sockets=1,cores=2,threads=1"
    qe.net_device = "virtio-net-pci"
    qe.extra_qemu_args = %w(-accel tcg,thread=multi,tb-size=512)
    qe.qemu_dir = "/usr/local/share/qemu"
  end
end
```

7. Force Local IP

```
Vagrant.configure("2") do |config|
  config.vm.box = "debian/bullseye64"

  config.vm.provider "qemu" do |qe|
    qe.extra_netdev_args = "net=192.168.51.0/24,dhcpstart=192.168.51.10"
  end
end
```

8. Windows host

Windows version QEMU doesn't support `daemonize` mode and unix socket

```
Vagrant.configure("2") do |config|
  # ... other stuff

  config.vm.provider "qemu" do |qe|
    qe.no_daemonize = true
    qe.control_port = 33333
    qe.debug_port = 33334
  end
end
```

9. Auto port collisions for ssh port (multiple machine)

```
Vagrant.configure("2") do |config|

  config.vm.define "vm1" do |c|
    c.vm.box = "ppggff/centos-7-aarch64-2009-4K"
    c.vm.provider "qemu" do |qe|
      qe.memory = "2G"
      qe.ssh_auto_correct = true
    end
    c.vm.synced_folder ".", "/vagrant", disabled: true
  end

  config.vm.define "vm2" do |c|
    c.vm.box = "ppggff/centos-7-aarch64-2009-4K"
    c.vm.provider "qemu" do |qe|
      qe.memory = "2G"
      qe.ssh_auto_correct = true
    end
    c.vm.synced_folder ".", "/vagrant", disabled: true
  end

end
```

10. Use socket_vmnet to communicate between machines

Thanks example from @Leandros.

See [pr#73](https://github.com/ppggff/vagrant-qemu/pull/73) for details.

11. Improved VM I/O performance

When creating the disks that are attached, each disk is an id assign in order
they appear in the `Vagrantfile`. The primary disk has the `id` of `disk0`.

```ruby
Vagrant.configure("2") do |config|
  # ... other stuff

  config.vm.provider "qemu" do |qe|
    # Use a `none` drive interface.
    qe.drive_interface = "none"
    qe.extra_drive_args = "cache=none,aio=threads"

    # To improve I/O performance, create a separate I/O thread.
    # We refer to the primary disk as `disk0`.
    qe.extra_qemu_args = %w(
        -object iothread,id=io1
        -device virtio-blk-pci,drive=disk0,iothread=io1
    )
  end
end
```

See the [QEMU Documentation](https://www.qemu.org/docs/master/devel/multiple-iothreads.html) and [heiko-sieger.info/tuning-vm-disk-performance/](https://www.heiko-sieger.info/tuning-vm-disk-performance/) for more details.

12. Advanced networking with private_network

Pick a backend with `net_mode`: QEMU's native vmnet.framework on macOS (requires sudo), TAP on Linux, or the `socket` netdev. The `:socket` backend is a thin wrapper around QEMU's `socket` netdev — you choose the mode in `socket_opts`: `mcast=` (multicast, N-way, Linux/Windows) or `listen=`/`connect=` (point-to-point, no root, works on macOS). The plugin creates two NICs: NIC 0 (user-mode for SSH and port forwarding) and NIC 1 (platform backend for VM networking). The static IP is delivered via a cloud-init NoCloud seed ISO that the plugin builds and attaches automatically; the NICs are matched by MAC address, never by interface order.

For VM-to-VM networking on macOS without sudo, use `:socket` with a `listen`/`connect` pair — you decide which VM listens and which connects:

```ruby
Vagrant.configure("2") do |config|
  PORT = 12399
  # vm1 listens; define it first so it is up before vm2 connects.
  config.vm.define "vm1" do |c|
    c.vm.box = "perk/ubuntu-2204-arm64"  # an aarch64 cloud-init box
    c.vm.network "private_network", ip: "192.168.105.51"
    c.vm.provider "qemu" do |qe|
      qe.advanced_network = true
      qe.net_mode = :socket
      qe.socket_opts = "listen=127.0.0.1:#{PORT}"
      qe.ssh_auto_correct = true
    end
  end
  # vm2 connects to vm1.
  config.vm.define "vm2" do |c|
    c.vm.box = "perk/ubuntu-2204-arm64"
    c.vm.network "private_network", ip: "192.168.105.52"
    c.vm.provider "qemu" do |qe|
      qe.advanced_network = true
      qe.net_mode = :socket
      qe.socket_opts = "connect=127.0.0.1:#{PORT}"
      qe.ssh_auto_correct = true
    end
  end
end
```

A single VM with a static IP (vmnet is the default backend on macOS when `net_mode` is `:auto`):

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ppggff/centos-7-aarch64-2009-4K"
  config.vm.network "private_network", ip: "192.168.105.10"

  config.vm.provider "qemu" do |qe|
    qe.advanced_network = true
    # qe.net_mode = :vmnet_shared  # default on macOS when :auto
  end
end
```

Notes:
* The guest image must include cloud-init, otherwise the static IP is silently not applied
* On macOS, vmnet requires root: run `sudo vagrant up` (and the other lifecycle commands such as `halt`/`reload`/`destroy`), because the plugin launches QEMU as a child of the Vagrant process and does not elevate it on its own. The plugin warns when vmnet is selected and Vagrant is not running as root.
* Side effect of running under `sudo`: QEMU and everything it writes become **root-owned** — the per-VM data directory (`.vagrant/machines/<name>/qemu/` in your project) and any box Vagrant downloads while elevated (`~/.vagrant.d/boxes/<box>/`). A later command run **without** `sudo` then fails with `EACCES` — e.g. a plain `vagrant status`/`up`, an unprivileged test run, or switching to a rootless backend — often on the box's `box_update_check` file. To handle it, either keep using `sudo` consistently for that environment, or restore ownership:
  ```sh
  sudo chown -R "$(id -un)":staff ~/.vagrant.d/boxes/<box> .vagrant
  ```
  Pre-adding boxes as your normal user (`vagrant box add <box>`) before the first `sudo vagrant up` also avoids the box ending up root-owned.
* To avoid root (and this side effect) entirely on macOS, use [`socket_vmnet`](https://github.com/lima-vm/socket_vmnet) — a small root helper daemon you install once, which QEMU then connects to as a normal user (the approach Lima/Colima/minikube take). The `com.apple.developer.networking.vmnet` entitlement could also bypass root in principle, but it is a *restricted* Apple entitlement that requires an Apple-provisioned signing certificate and cannot be ad-hoc / self-signed onto Homebrew's QEMU, so it is not a practical option for individual users.
* Without `advanced_network = true`, the `private_network` configuration is ignored with a warning
* When only one NIC is needed (no `private_network`), no cloud-init seed is attached, avoiding compatibility issues
* Combining `advanced_network` with `config.vm.cloud_init` is supported: the plugin merges your user-data and the generated network-config into a single NoCloud seed
* The Linux `:tap` backend expects a pre-created tap device attached to a bridge, e.g.:
  `sudo ip tuntap add tap0 mode tap && sudo ip link set tap0 master br0 && sudo ip link set tap0 up`
* `socket_opts = "mcast=..."` gives N-way VM-to-VM on Linux/Windows, but does **not** work on macOS: QEMU binds the netdev socket to the multicast group address, which the Darwin socket stack refuses to send from (`EADDRNOTAVAIL`). On macOS use a `listen`/`connect` pair (no root) or vmnet (sudo).
* `socket_opts = "listen=..."` / `"connect=..."` is a point-to-point QEMU TCP link and connects **exactly two** VMs (QEMU's listening socket accepts a single connection — it is not a hub). You choose which VM listens and which connects. The listener must be running before the connector starts, so define the listener first and bring the environment up together (`vagrant up`); starting a connector alone, or reloading the listener, drops the link.

Platform support:

| Platform | Backend (`net_mode`) | Host ↔ VM | VM ↔ VM | Root? | External dependency |
|----------|---------|:---------:|:-------:|:-----:|:-------------------:|
| macOS    | `:vmnet_shared`/`_host`/`_bridged` | Yes | Yes | sudo (or socket_vmnet) | None (QEMU >= 7.0) |
| macOS    | `:socket` (`listen`/`connect`) | No (use port forwarding) | Yes (2 VMs) | No | None |
| Linux    | `:tap` + bridge | Yes | Yes | sudo | Pre-created tap device + bridge (`ip` command) |
| Linux    | `:socket` (`mcast`) | No (use port forwarding) | Yes | No | None |
| Windows  | `:socket` (`mcast`) | No (use port forwarding) | Yes | No | None |

(`socket_opts = "mcast=..."` is not usable on macOS — see the note above; use a `listen`/`connect` pair there.)

## Debug

Serial port is exported to unix socket: `<user_home>/.vagrant.d/tmp/vagrant-qemu/<id>/qemu_socket_serial`, or `debug_port`.

To debug and login to the GuestOS from serial port:

* unix socket
  1. Get the id: `.vagrant/machines/default/qemu/id` in same directory with `Vagrantfile`
  2. Get the path to `qemu_socket_serial`
  3. Use `nc` to connect: `nc -U /Users/.../qemu_socket_serial`
* `debug_port` (for example: 33334)
  * Use `nc` to connect: `nc localhost 33334`

To send ctrl+c to GuestOS from `nc`, try:
* unix socket
  * `echo 03 | xxd -r -p | nc -U /Users/.../qemu_socket_serial`
* `debug_port` (for example: 33334)
  * `echo 03 | xxd -r -p | nc localhost 33334`

## Build

To build the `vagrant-qemu` plugin 

**Development Environment:**

Ensure your development environment has the necessary tools installed, such as:

* **Ruby**:
    * [Ruby installation](https://www.ruby-lang.org/en/documentation/installation/)
    * [Ruby Version Manager (RVM)](https://rvm.io/rvm/install)
    * [Ruby Installer for Windows](https://rubyinstaller.org/)
* [Bundler](https://bundler.io/):
    ```sh
    gem install bundler
    ```
* [Rake](https://github.com/ruby/rake)
    ```sh
    gem install rake
    ```

1. Clone this repository:
    ```sh
    git clone https://github.com/ppggff/vagrant-qemu.git
    cd vagrant-qemu
    ```

2. Use [bundler](http://gembundler.com) to install the necessary dependencies to ensure all required Ruby gems are available for buidling the plugin out
    ```sh
    bundle config set --local path 'vendor/bundle'
    bundle install
    ```
    > This command tells Bundler to install gems in the vendor/bundle directory within your project.

3. Use `rake` to build the plugin. This command will package your changes into a gem file:

    ```sh
    bundle exec rake build
    ```
    > After running this command, you should see a `.gem` file created in the `pkg` directory within the repository. This file represents your built plugin.

4. Use `vagrant plugin install` to install the plugin from the local `.gem` file. This ensures that Vagrant uses the locally built version.
    
    ```sh
    vagrant plugin install ./pkg/vagrant-qemu-<version>.gem
    ```

    > Replace `<version>` with the actual version number of the locally built `.gem` file

### Check Installed Plugins

After installation, verify that the locally built `vagrant-qemu` plugin is installed by running:

```sh
vagrant plugin list | grep vagrant-qemu
```

> This command will list all installed plugins, and you should see the vagrant-qemu plugin with the locally built version.

### Running Tests

```sh
# Unit tests (fast, no QEMU needed)
bundle exec rake spec:unit

# Acceptance tests (mock QEMU, no real VM)
bundle exec rake spec:acceptance

# End-to-end tests (requires QEMU and a box image). e2e exercises the
# INSTALLED plugin — rebuild and reinstall first (the suite fails fast on
# a version mismatch):
bundle exec rake build
vagrant plugin install ./pkg/vagrant-qemu-<version>.gem
TEST_QEMU=1 bundle exec rake spec:e2e

# End-to-end with vmnet (requires sudo + macOS; needs an aarch64 cloud-init box)
TEST_QEMU=1 TEST_VMNET=1 TEST_BOX_CLOUDINIT=perk/ubuntu-2204-arm64 sudo -E bundle exec rake spec:e2e

# All tests
bundle exec rake spec
```

## Known issue / Troubleshooting

### 1. failed to create shared folder

```
We couldn't detect an IP address that was routable to this
machine from the guest machine! Please verify networking is properly
setup in the guest machine and that it is able to access this
host.

As another option, you can manually specify an IP for the machine
to mount from using the `smb_host` option to the synced folder.
```

The reason is that the user mode of qemu currently in use does not support ping.
`smb_host` needs to be explicitly specified. For example:

```
Vagrant.configure("2") do |config|
  # ... other stuff

  config.vm.synced_folder ".", "/vagrant", type: "smb", smb_host: "10.0.2.2"
end
```

As an alternative solution(helpful for macOS) it is possible to use 9p file system via virtio. 

```
config.vm.synced_folder ".", "/vagrant", disabled: true
config.vm.provider "qemu" do |qe|
    qe.extra_qemu_args = %w(-virtfs local,path=.,mount_tag=shared,security_model=mapped)
end
```
This will pass "current directory" to mount point tagged "shared"
Use the following /etc/fstab entry on the vagrant vm to mount the shared directory into /home/vagrant/shared
```
shared /home/vagrant/shared 9p _netdev,trans=virtio,msize=524288 0
```
Please keep in mind that the guest OS will need to install 9p dependencies to handle the 9p filestystem.

### 2. netcat does not support the -U parameter

I had netcat installed through home brew and it does not support the -U parameter.

I fixed it by uninstalling netcat in home brew brew uninstall netcat

Thanks @kjeldahl fix this at [issue #6](https://github.com/ppggff/vagrant-qemu/issues/6)

### 3. Vagrant SMB synced folders require the account password to be stored in an NT compatible format

If you get this error when running `vagrant up`

1. On your M1 Mac, go to System Preferences > Sharing > File Sharing > Options...
2. Tick "Share Files and Folders using SMB"
3. Tick your username
4. Click Done
5. Run `vagrant up` again

### 4. The box you're using with the QEMU provider ('default') is invalid

`qemu_dir` is auto-detected (Homebrew prefix / per-host default) and is only
needed for **aarch64** firmware — x86_64 boots on SeaBIOS and no longer
validates it. If detection still picks the wrong path for an aarch64 box
(e.g. a MacPorts or custom QEMU install), set it explicitly. Find the correct
one with:
```
echo `brew --prefix`/share/qemu
```

Then either export `QEMU_DIR` / `HOMEBREW_PREFIX`, or set it in the `Vagrantfile`:
```
config.vm.provider "qemu" do |qe|
  qe.qemu_dir = "/usr/local/share/qemu"
end
```

### 5. `conflicting dependencies logger (= 1.6.0) and logger (= 1.6.1)` when installing the plugin

This is a Vagrant 2.4.2 packaging bug (bundled `logger` gem version conflict),
not a problem with this plugin — see
[hashicorp/vagrant#13534](https://github.com/hashicorp/vagrant/issues/13534).
Upgrade Vagrant to **2.4.3 or newer** (the Homebrew cask may lag; install the
official build from [vagrantup.com](https://www.vagrantup.com/downloads) if
needed). Do **not** work around it by pinning `logger` in a Gemfile — that tends
to deepen the conflict.

## TODO

* Support NFS shared folder
* Support package VM to box
* More configures
* GUI mode
