# Package a guest and boot a fresh copy

This recipe boots a source VM, writes a random marker inside its guest disk,
packages it, destroys the source VM, then imports the box into a fresh project.
It requires the fresh guest to return the exact marker and checks that the
exported qcow2 image has no backing-file dependency. Synced folders are disabled
in both Vagrantfiles.

## Prerequisites

Install Vagrant, Ruby, QEMU (`qemu-img` and the system binary for your guest
architecture), Bash and tar. The default box is `cloud-image/debian-12` for the
host architecture. An internet connection is needed if it is not cached.

Build and install the plugin from the same repository checkout as this recipe:

```sh
gem build vagrant-qemu.gemspec
plugin_gem="vagrant-qemu-$(ruby -Ilib -rvagrant-qemu/version -e 'print VagrantPlugins::QEMU::VERSION').gem"
vagrant plugin install "$plugin_gem"
```

Older plugin versions may return `Function not supported` for `vagrant package`.
Keep the source commit with your test results, since it identifies the tested
implementation more precisely than the gem version alone.

On Debian ARM64, if the firmware package uses AAVMF names, prepare a directory
with the names expected by the plugin and keep `QEMU_DIR` set:

```sh
mkdir -p firmware
ln -s /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd firmware/edk2-aarch64-code.fd
ln -s /usr/share/AAVMF/AAVMF_VARS.fd firmware/edk2-arm-vars.fd
export QEMU_DIR="$PWD/firmware"
```

Those files are supplied by Debian's `qemu-efi-aarch64` package. Homebrew QEMU
normally supplies the expected filenames directly.

## Run the exact recipe used by CI

From the repository root, choose a workspace with no existing source/consumer
projects or package artifacts:

```sh
git rev-parse HEAD
examples/package-roundtrip/run.sh /tmp/qemu-package-proof
```

Successful output includes:

```text
Exported image: standalone qcow2
Package round-trip verified: package-roundtrip-<random hexadecimal token>
Reusable box retained at: /tmp/qemu-package-proof/portable.box
```

The script destroys its two VMs and removes its temporary box registration on
exit. It retains `portable.box`, the copied Vagrantfiles, extracted box contents,
`image-info.json` and `verified-marker.txt` in the workspace. Use a fresh workspace
for another run. `TEST_BOX` can select another box compatible with the host;
`TEST_BOX_VERSION` selects a specific version of that source box.

## Recorded local verification

Verified on 2026-10-12 using Linux ARM64 (Raspberry Pi), KVM, Vagrant 2.4.9,
QEMU 10.0.13 and plugin/recipe source commit
[`04baba0`](https://github.com/antimatter-studios/vagrant-qemu/commit/04baba0422f380b6fc0ffabf7fa06bcaf7d10026).
The source was `cloud-image/debian-12`, ARM64, version `20260909.2596.0`.

After the firmware setup above, the command was:

```sh
TEST_BOX_VERSION=20260909.2596.0 examples/package-roundtrip/run.sh /tmp/qemu-package-proof
```

The source VM was destroyed before the consumer was created. The run exited with
status zero and reported:

```text
Exported image: standalone qcow2
Package round-trip verified: package-roundtrip-3dfb0a8f40f2ddda9361f6bb5a21b750
```

The exported image had a 10 GiB virtual size and no backing filename. This is a
Linux/KVM result. CI executes the same script on Linux, macOS and inside Windows
WSL2; the hosted macOS recipe uses TCG because those runners lack HVF. On Windows,
run the shell recipe inside WSL2.

## What the recipe executes

The script copies [source/Vagrantfile](source/Vagrantfile) into a fresh source
project and runs these steps, using its generated marker and box name:

```sh
vagrant up --provider=qemu
vagrant ssh -c "printf '%s\\n' '$marker' > ~/package-roundtrip-marker && sync"
vagrant package --output "$workspace/portable.box"
vagrant destroy -f
vagrant box add "$PACKAGE_BOX_NAME" "$workspace/portable.box"
```

It then copies [consumer/Vagrantfile](consumer/Vagrantfile) into a separate project
and runs:

```sh
vagrant up --provider=qemu
vagrant ssh -c 'cat ~/package-roundtrip-marker'
```

`libvirt` is the archive format accepted by this plugin; the running VM's provider
is `qemu`. Let `vagrant box add` read the provider from the archive metadata;
explicitly passing `--provider=libvirt` can trigger installation of the libvirt
plugin, which this recipe does not require. The box includes guest changes on the box disks, its architecture and
the packaged SSH configuration. Extra disks, DVDs and cloud-init seed ISOs are
excluded. Configure host networking and synced folders in the consuming project.

To reuse the retained archive later, add it under a name of your choice and use
the consumer Vagrantfile with `PACKAGE_BOX_NAME` set to that name.
