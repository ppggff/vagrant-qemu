# Overview

This directory contains the necessary files to set up and test a virtual machine using Vagrant with QEMU as the provider. The setup includes NUMA node configuration and custom QEMU settings. It assumes that you have followed the prerequistes detailed in the [primary documentation](../../README.md).

## Contents

- **get_numa_info.sh**: A script to gather NUMA information from the host system. This script outputs CPU-to-NUMA node mappings to a file, which is used by the Vagrantfile for VM configuration.

- **qemu_config.yml**: A YAML configuration file containing paths and settings for the custom QEMU build. This file is read by the Vagrantfile to configure the QEMU provider.

- **numactl-Vagrantfile**: The Vagrant configuration file that defines the VM setup for NUMA node bindings. It uses the `qemu` provider and custom settings specified in `qemu_config.yml`.

## Setup Instructions

You can change the default `generic/ubuntu2204` box for the VM in the [Vagrant Public Registry](https://portal.cloud.hashicorp.com/vagrant/discover?architectures=amd64&next=CgxXekk1TWpVM05WMD0%3D&providers=qemu).

1. **Generate NUMA Information**:
   Run the `get_numa_info.sh` script to gather NUMA information from the host. This will create a file `/tmp/numa_info.txt` with the necessary mappings.

   ```bash
   bash get_numa_info.sh
   ```

2. **Copy the files**: Copy the files `qemu_config.yml` and `numactl-Vagrantfile` to a temp directory.

    ```bash
    mkdir /tmp/test-qemu-numactl
    cp ./qemu_config.yml /tmp/test-qemu-numactl
    cp ./numactl-Vagrantfile /tmp/test-qemu-numactl/Vagrantfile
    cd /tmp/test-qemu-numactl
    ```

3. **Configure QEMU Settings**: Ensure that `qemu_config.yml` is correctly configured with the paths to your custom QEMU build. The file should include entries like:

   ```bash
   custom_qemu_bin: "/path/to/custom/qemu/bin/qemu-system-x86_64"
   custom_qemu_dir: "/path/to/custom/qemu"
   ```

3. **Run Vagrant**: Use Vagrant to bring up the virtual machine defined in the Vagrantfile. This will use the NUMA information and QEMU settings to configure the VM.

   ```bash
   vagrant up
   ```

   This command will start the VM with the specified configuration, including NUMA node bindings.

4. **Log into the VM**: Connect to the VM and explore

    ```bash
    vagrant ssh
    ```

5. **Clean up**: Once you are finished running whatever experiments

    ```bash
    vagrant destroy -f
    ```

### Notes

* Ensure that the `get_numa_info.sh` script is executable. You can set the executable permission with:

    ```bash
    chmod +x get_numa_info.sh
    ```

* Verify that the paths in `qemu_config.yml` are correct and accessible.
* The Vagrantfile assumes that the NUMA information is stored in `/tmp/numa_info.txt`. Ensure this file is generated before running `vagrant up`.

By following these instructions, you can set up and test the virtual machine with NUMA configuration using Vagrant and QEMU.

## Exploration

This section walks through an exploration of the enviornment to determine what has been launched and how to investigate various artifacts.

1. Get the pid of the VM:

    ```bash
    cd $HOME
    find . -type f -name *.pid
    ./.vagrant.d/tmp/vagrant-qemu/vq_vtlymSCoO-Q/qemu.pid
    cat ./.vagrant.d/tmp/vagrant-qemu/vq_vtlymSCoO-Q/qemu.pid
    109245
    ```

2. Explore the NUMA node pinning:

    ```bash
    numactl --show --pid 109245
    policy: default
    preferred node: current
    physcpubind: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95
    cpubind: 0 1 2 3 4 5 6 7
    nodebind: 0 1 2 3 4 5 6 7
    membind: 0 1 2 3 4 5 6 7
    preferred:
    ```

    > The `cpubind` and `nodebind` outputs indicate that the VM process is restricted to CPUs and memory from nodes 0-7.

# Known Issues

The `vagrant destroy` command does not properly clean up the `qemu` VM, [see #35](https://github.com/ppggff/vagrant-qemu/issues/35)

* To clean up, view the full command using the `pid` of the VM:

    ```bash
    ps -p 109245 -o pid,ppid,user,start,cmd --width 1500 | cat
    PID    PPID USER      STARTED CMD
    109245       1 enpicket 14:48:49 /usr/bin/qemu-system-x86_64 -machine type=q35,accel=kvm -cpu host -smp 4 -m 12288 -device virtio-net-pci,netdev=net0 -netdev user,id=net0,hostfwd=tcp::50022-:22 -drive if=virtio,id=disk0,format=qcow2,file=/home/enpicket/git-repos/vagrant-qemu/examples/numactl/.vagrant/machines/numactl-test-vm/qemu/vq_vtlymSCoO-Q/linked-box.img -chardev socket,id=mon0,path=/home/enpicket/.vagrant.d/tmp/vagrant-qemu/vq_vtlymSCoO-Q/qemu_socket,server=on,wait=off -mon chardev=mon0,mode=readline -chardev socket,id=ser0,path=/home/enpicket/.vagrant.d/tmp/vagrant-qemu/vq_vtlymSCoO-Q/qemu_socket_serial,server=on,wait=off -serial chardev:ser0 -pidfile /home/enpicket/.vagrant.d/tmp/vagrant-qemu/vq_vtlymSCoO-Q/qemu.pid -daemonize -parallel null -monitor none -display none -vga none
    ```

    > Note in this case, the pid is `109245` also, note the socket `/home/enpicket/.vagrant.d/tmp/vagrant-qemu/vq_vtlymSCoO-Q/qemu_socket`

    * Try connecting to the VM socket and issuing a shutdown:

    ```bash
    export VM_PID=109245 # REPLACE WITH YOUR VM's PID
    export QEMU_SOCKET="/home/enpicket/.vagrant.d/tmp/vagrant-qemu/vq_vtlymSCoO-Q/qemu_socket"
    # REPLACE THE ABOVE WITH THE PATH TO YOUR SOCKET
    socat UNIX-CONNECT:$QEMU_SOCKET stdio
    (qemu) system_powerdown
    ```

    * If this fails with the error: `No such file or directory`, issue a graceful shutdown:

    ```bash
    kill -15 $VM_PID
    ```

