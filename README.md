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
* Pin NUMA nodes, see [numactl repo](https://github.com/numactl/numactl)

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

### Installing numactl

The `numactl_args` option is only available on Linux hosts and requires the `numactl` tool to be installed on your system.

- **Debian/Ubuntu**:  
  ```sh
  sudo apt-get install numactl
  ```
- **RHEL/CentOS/Fedora**:  
  ```sh
  sudo dnf install numactl
  ```
- **Arch Linux**:  
  ```sh
  sudo pacman -S numactl
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
  * `arch` - The architecture of VM, default: `aarch64`
  * `machine` - The machine type of VM, default: `virt,accel=hvf,highmem=off`
  * `cpu` - The cpu model of VM, default: `cortex-a72`
  * `smp` - The smp setting (Simulate an SMP system with n CPUs) of VM, default: `2`
  * `memory` - The memory setting of VM, default: `4G`
  * `disk_resize` - The target disk size of the primary disk, requires resizing of filesystem inside of VM, default: `nil`.
* debug/expert
  * `ssh_host` - The SSH IP used to access VM, default: `127.0.0.1`
  * `ssh_auto_correct` - Auto correct port collisions for ssh port, default: `false`
  * `net_device` - The network device, default: `virtio-net-device`
  * `drive_interface` - The interface type for the main drive, default `virtio`
  * `image_path` - The path (or array of paths) to qcow2 image for box-less VM, default is nil value
  * `qemu_bin` - Path to an alternative QEMU binary, default: autodetected
  * `qemu_dir` - The path to QEMU's install dir, default: `/opt/homebrew/share/qemu`
  * `extra_qemu_args` - The raw list of additional arguments to pass to QEMU. Use with extreme caution. (see "Force Multicore" below as example)
  * `extra_netdev_args` - extra, comma-separated arguments to pass to the -netdev parameter. Use with caution. (see "Force Local IP" below as example)
  * `extra_drive_args` - Add optional extra arguments to each drive attached, default: `[]`
  * `control_port` - The port number used to control vm from vagrant, default is nil value. (nil means use unix socket)
  * `debug_port` - The port number used to export serial port of the vm for debug, default is nil value. (nil means use unix socket, see "Debug" below for details)
  * `no_daemonize` - Disable the "daemonize" mode of QEMU, default is false. (see "Windows host" below as example)
  * `firmware_format` - The format of aarch64 firmware images (`edk2-aarch64-code.fd` and `edk2-arm-vars.fd`) loaded from `qemu_dir`, default: `raw`
  * `other_default` - The other default arguments used by this plugin, default: `%W(-parallel null -monitor none -display none -vga none)`
  * `extra_image_opts` - Options passed via `-o` to `qemu-img` when the base qcow2 images are created, default: `[]`
  * `numactl_args` - Pin specific NUMA nodes using `numactl`. 
    > Available on Linux hosts and requires the `numactl` tool to be installed on your system. 
    > If `numactl` is not installed, QEMU startup will fail if you set this option.

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

12. **(Optional)**: Pin QEMU with numactl (Linux only)

    In your `Vagrantfile`:
    ```ruby
    config.qemu.numactl_args = ['--cpunodebind=0', '--membind=0']
    ```

    This will prepend your specified arguments to the QEMU launch command, e.g.:

    ```sh
    numactl --cpunodebind=0 --membind=0 qemu-system-x86_64 ...
    ```

See the [QEMU Documentation](https://www.qemu.org/docs/master/devel/multiple-iothreads.html) and [heiko-sieger.info/tuning-vm-disk-performance/](https://www.heiko-sieger.info/tuning-vm-disk-performance/) for more details.

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

This may cause by invalid default qemu dir (`/opt/homebrew/share/qemu`).

You can find the correct one by:
```
echo `brew --prefix`/share/qemu
```

And then set it (for example `/usr/local/share/qemu`) in the `Vagrantfile` as:
```
config.vm.provider "qemu" do |qe|
  qe.qemu_dir = "/usr/local/share/qemu"
end
```

## TODO

* Support NFS shared folder
* Support package VM to box
* More configures
* Better error messages
* Network
* GUI mode
