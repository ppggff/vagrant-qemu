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
* Start VM without GUI
* SSH into VM
* Provision the instances with any built-in Vagrant provisioner
* Synced folder support via SMB
* Basic operation: up, ssh, halt, destroy
* Basic suport to forwarded ports, see [vagrant doc](https://www.vagrantup.com/docs/networking/forwarded_ports) for details

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

This provider exposes a few provider-specific configuration options:

* `ssh_port` - The SSH port number used to access VM (IP is 127.0.0.1),
  default: `50022`
* `arch` - The architecture of VM, default: `aarch64`
* `machine` - The machine type of VM, default: `virt,accel=hvf,highmem=off`
* `cpu` - The cpu model of VM, default: `cortex-a72`
* `smp` - The smp setting (Simulate an SMP system with n CPUs) of VM, default: `2`
* `accel` - select accelerator (kvm, xen, hax, hvf, nvmm, whpx or tcg) with properties, default is nil value
* `memory` - The memory setting of VM, default: `4G`
* `net_device` - The network device, default: `virtio-net-device`
* `image_path` - The path to qcow2 image for box-less VM, default is nil value
* `qemu_dir` - The path to QEMU's install dir, default: `/opt/homebrew/share/qemu`

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
    qe.cpu = "max"
    qe.net_device = "virtio-net-pci"
  end
end
```

5. Force Multicore
Force multicore may improve speed of emulation but also might result in unstable and incorrect emulation.

```
Vagrant.configure(2) do |config|
  config.vm.box = "centos/7"

  config.vm.provider "qemu" do |qe|
    qe.arch = "x86_64"
    qe.machine = "q35"
    qe.cpu = "max"
    qe.accel = "tcg,thread=multi,tb-size=512"
    qe.net_device = "virtio-net-pci"
  end
end
```

6. Forwarded ports

```
# Basic Vagrant config (API version 2)
Vagrant.configure(2) do |config|
  # ... other stuff

  config.vm.network "forwarded_port", guest: 80, host: 8080
end
```

## Debug

Serial port is exported to unix socket: `<user_home>/.vagrant.d/tmp/vagrant-qemu/<id>/qemu_socket_serial`.
To debug and login to the GuestOS from serial port:

1. Get the id: `.vagrant/machines/default/qemu/id` in same directory with `Vagrantfile`
2. Get the path to `qemu_socket_serial`
3. Use `nc` to connect: `nc -U /Users/.../qemu_socket_serial`

To send ctrl+c to GuestOS from `nc`, try `echo 03 | xxd -r -p | nc -U /Users/.../qemu_socket_serial`

## Build

To build the `vagrant-qemu` plugin, clone this repository out, and use
[Bundler](http://gembundler.com) to get the dependencies:

```
bundle
```

Once you have the dependencies, build with `rake`:

```
bundle exec rake build
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

## TODO

* Support NFS shared folder
* Support package VM to box
* More configures
* Better error messages
* Network
* GUI mode
