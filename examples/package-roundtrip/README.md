# Package a guest and boot a fresh copy

This recipe verifies that guest disk data survives `vagrant package` and can
be read after importing the archive into a fresh project.

## Prerequisites

Install Vagrant, Ruby, QEMU (`qemu-img` and the system binary for your guest
architecture), Bash and tar. The default box is `cloud-image/debian-12` for the
host architecture; an internet connection is needed if it is not cached.
On Windows, run the recipe inside WSL2.

Build and install the plugin from the repository root:

```sh
gem build vagrant-qemu.gemspec
plugin_gem="vagrant-qemu-$(ruby -Ilib -rvagrant-qemu/version -e 'print VagrantPlugins::QEMU::VERSION').gem"
vagrant plugin install "$plugin_gem"
```

On Debian ARM64, if the firmware package uses AAVMF names, create the filenames
expected by the plugin and keep `QEMU_DIR` set when running the recipe:

```sh
mkdir -p firmware
ln -s /usr/share/AAVMF/AAVMF_CODE.no-secboot.fd firmware/edk2-aarch64-code.fd
ln -s /usr/share/AAVMF/AAVMF_VARS.fd firmware/edk2-arm-vars.fd
export QEMU_DIR="$PWD/firmware"
```

Those files are supplied by Debian's `qemu-efi-aarch64` package.

## Run the recipe

From the repository root, use a workspace path that does not already contain
the recipe's source or consumer projects:

```sh
examples/package-roundtrip/run.sh /tmp/qemu-package-proof
```

The script destroys its two VMs and removes its temporary box registration when
it exits. It retains the reusable archive at
`/tmp/qemu-package-proof/portable.box`. Set `TEST_BOX` to use another box
compatible with the host, or `TEST_BOX_VERSION` to select a specific version.

See the [main README](../../README.md#package-a-qemu-machine-into-a-reusable-box)
for the manual `vagrant package` and archive reuse steps.
