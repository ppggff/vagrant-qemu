# Vagrant QEMU Provider

This is a Vagrant plugin that adds a simple QEMU provider to Vagrant, allowing Vagrant
to control and provision machines using QEMU.

**Notes: test with Apple Silicon / M1 and CentOS aarch64 image only**

## Features

* Import from a Libvirt vagrant box or qcow2 image
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

5. Forwarded ports

```
# Basic Vagrant config (API version 2)
Vagrant.configure(2) do |config|
  # ... other stuff

  config.vm.network "forwarded", guest: 80, host: 8080
end
```

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

## TODO

* Support NFS shared folder
* Support package VM to box
* More configures
* Better error messages
* Network
* GUI mode
