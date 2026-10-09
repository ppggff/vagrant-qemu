# CI guest smoke test

This project boots a small Debian guest with the current QEMU provider. It
uses QEMU's software emulation so it can run on GitHub-hosted Linux and macOS
runners, where hardware virtualization may not be available. CI also runs the
same project inside WSL2 on a Windows runner, with the VM files copied to the
WSL filesystem.

With Vagrant, QEMU, and this plugin installed, run:

```sh
CI_TEST_ARCH=arm64 vagrant up --provider=qemu --no-provision
vagrant ssh -c 'uname -a'
vagrant halt
vagrant destroy -f
```

Use `CI_TEST_ARCH=amd64` on an x86_64 host. The CI workflow runs this example
without VirtioFS or other proposed provider changes.
