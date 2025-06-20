# Overview

This directory contains a sample Vagrantfile for use on an `x86_64` architecture. The
[`x86_64-Vagrantfile`](./x86_64-Vagrantfile) overrides the following default options:

| Option       | Default                      | Override                    |
| :----------- | :--------------------------: | --------------------------: |
| `machine`    | virt,accel=hvf,highmem=off   | type=q35,accel=kvm          |
| `qemu_dir`   | /opt/homebrew/share/qemu     | /usr/share/qemu             |
| `qemu_bin`   | autodetected                 | /usr/bin/qemu-system-x86_64 |
| `cpu`        | cortex-a72                   | host                        |
| `net_device` | virtio-net-device            | virtio-net-pci              |   

For additional overrides or additions, see the [Options](https://github.com/ppggff/vagrant-qemu?tab=readme-ov-file#options) section of the main [README](../../../README.md)

## Host Configuration

* **Model name**: Intel(R) Xeon(R) CPU Max 9468 
* **Architecture**: x86_64
* **Operating System**: Ubuntu 24.04.1 LTS

## Prerequisites/Assumptions

1. Your system supports virtualization
2. You have a system user with administrative privileges
3. You have installed:
    * [Vagrant](https://developer.hashicorp.com/vagrant/docs/installation)
    * [QEMU with KVM backing](https://linuxconfig.org/setting-up-virtual-machines-with-qemu-kvm-and-virt-manager-on-debian-ubuntu)
4. You have access to the internet (to download the box)

# To Use

1. Copy the `x86_64-Vagrantfile` to `Vagrantfile`:

    ```bash
    cp x86_64-Vagrantfile Vagrantfile
    ```

2. Run `vagrant up`:

    ```bash
    vagrant up
    Bringing machine 'default' up with 'qemu' provider...
    ==> default: Checking if box 'generic/ubuntu2204' version '4.3.12' is up to date...
    ==> default: Warning! The QEMU provider doesn't support any of the Vagrant
    ==> default: high-level network configurations (`config.vm.network`). They
    ==> default: will be silently ignored.
    ==> default: Starting the instance...
    ==> default: Waiting for machine to boot. This may take a few minutes...
        default: SSH address: 127.0.0.1:50022
        default: SSH username: vagrant
        default: SSH auth method: private key
        default:
        default: Vagrant insecure key detected. Vagrant will automatically replace
        default: this with a newly generated keypair for better security.
        default:
        default: Inserting generated public key within guest...
        default: Removing insecure key from the guest if it's present...
        default: Key inserted! Disconnecting and reconnecting using new SSH key...
    ==> default: Machine booted and ready!
    ```

3. SSH to the VM:

    ```bash
    vagrant ssh
    vagrant@ubuntu2204:~$ lsb_release -a
    No LSB modules are available.
    Distributor ID: Ubuntu
    Description:    Ubuntu 22.04.3 LTS
    Release:        22.04
    Codename:       jammy
    ```

4. Destroy the VM:
    
    ```bash
    vagrant destroy
    ```

# Resources

For additional boxes compatible with qemu, see [qemu amd64 boxes](https://portal.cloud.hashicorp.com/vagrant/discover?architectures=amd64&next=CghXekUzT0RCZA%3D%3D&providers=qemu) on the Vagrant Public Registry.
