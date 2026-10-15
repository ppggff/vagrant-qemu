# 0.1.0 (2021-12-15)

* Initial release.

# 0.1.1 (2021-12-30)

* Works with basic functions.

# 0.1.2 (2022-01-06)

* Support vm without box.

# 0.1.3 (2022-01-25)
# 0.1.4 (2022-01-25)
# 0.1.5 (2022-01-25)
# 0.1.6 (2022-01-25)

* Add config 'net_device'.

# 0.1.7 (2022-03-26)

* Add basic support to forwarded ports.
* Move unix_socket to `<user_home>/.vagrant.d/tmp`.

# 0.1.8 (2022-05-05)

* Fix port collision problem with default ssh port 2222.
* Export serial port to unix socket for debug.

# 0.1.9 (2022-08-01)

* Set default config for newer qemu (>=7.0.0)

# 0.2.0 (2022-08-31)

* Add config extra_qemu_args'.
* Refine error message, such as 'Invalid qemu dir'.
* Add a 'Force Multicore' to Readme.

# 0.3.0 (2022-09-16)

* Add config extra_netdev_args.
* Replace `nc` with ruby's socket
* Add config control_port, debug_port, no_daemonize config for window host

# 0.3.1 (2022-09-16)

* Fix missing :arch for driver.import(options)

# 0.3.2 (2022-09-20)

* Use kill 0 to check whether a process is running

# 0.3.3 (2022-10-11)

* Fix a compatibility issue about ruby 3.x

# 0.3.4 (2023-03-09)

* Add config 'drive_interface'.

# 0.3.5 (2023-07-27)

* Fix forwarded ports bug. #39
* Add config 'firmware_format', 'ssh_host', 'other_default'.
* Allow no cpu for riscv64.
* Allow more config options to be nil.
* Let id start with "vq_".

# 0.3.6 (2024-02-27)

* Config 'image_path' support array type
* Try to support libvirt box v2 format

# 0.3.7 (2025-02-02)

* Ignore exception after sending 'system_powerdown' cmd, fix windows halt error
* Move pid file to tmp dir
* Be able to auto correct ssh port collisions, new config: ssh_auto_correct

# 0.3.8 (2025-02-21)

* Fix regression that ssh_port is not working #68

# 0.3.9 (2025-02-22)

* Support ssh_port in string (need better error message)

# 0.3.10 (2025-05-06)

* Add support for `qemu_bin` to customize QEMU binary

# 0.3.11 (2025-05-06)

* Re-publish with repacked gem

# 0.3.12 (2025-05-19)

* Add support for extra `-drive` arguments
* Add `extra_image_opts` to customize image creation
* Add support for cloud-init and disks
* Add support for resizing disk on vm setup

# 0.4.1 (2026-06-22)

* `vagrant halt` now reaps QEMU even when the guest was already halted from
  inside (e.g. `sudo systemctl halt`), where the ACPI `system_powerdown` is a
  no-op. Halt escalates: `system_powerdown` -> wait `graceful_timeout` -> QEMU
  `quit` monitor command (clean: flushes and closes the disk images) -> wait
  `graceful_timeout` -> SIGKILL as a last resort (#79)

# 0.4.0 (2026-06-12)

* Advanced networking (opt-in, `advanced_network = true`): dual-NIC `private_network`
  support via vmnet (macOS), TAP (Linux), or the QEMU `socket` netdev, with
  deterministic MAC addresses; static IP delivered through a plugin-built cloud-init
  NoCloud seed ISO (MAC-matched, requires cloud-init in the guest). When
  `config.vm.cloud_init` is also set, its user-data and the generated
  network-config are merged into a single seed
* `net_mode = :socket` is now a thin wrapper around QEMU's `socket` netdev: the new
  `socket_opts` option is emitted verbatim, so you pick the mode yourself —
  `"mcast=230.0.0.1:1234"` (multicast, N-way) or `"listen=:1234"` / `"connect=host:1234"`
  (point-to-point, no root, works on macOS where multicast does not — QEMU binds the
  socket to the multicast group address, which Darwin rejects for sending). For
  listen/connect you decide which VM listens and which connects (it is a 1:1 link,
  not a hub). `mcast_addr` remains as a shortcut for the multicast address
* Fix SSH port not updated after forwarded-port collision auto-correction
* Persist only needed runtime state in options.yml; harden YAML loading
  (`safe_load`); `vagrant halt` reads back the persisted control_port
* Graceful shutdown on halt with configurable `graceful_timeout` (default 60s),
  force kill as fallback
* Host-aware defaults for `arch`/`machine`/`cpu`/`net_device`/`qemu_dir`: detect
  the host arch (Apple Silicon vs Intel) and OS, default to native acceleration
  (`hvf`/`kvm`/`whpx`) with `cpu=host` when guest arch matches the host, and to
  `accel=tcg`/`cpu=max` when emulating; resolve `qemu_dir` from
  `QEMU_DIR`/`HOMEBREW_PREFIX`/per-host path; skip the `qemu_dir` check for
  x86_64 (SeaBIOS) so Intel Macs no longer fail with "Invalid qemu dir" (#59, #50)
* Validate the QEMU binary exists before starting the VM
* Destroy failures now surface the underlying error and preserve the machine ID
* Warn when private_network is configured without `advanced_network`, when the
  network backend needs sudo, and when other unsupported network types are used
* Add test suite: unit + acceptance + e2e (`rake spec:unit|acceptance|e2e`)

# 0.5.0 (2026-07-11)

* `vagrant package` is now supported: export a running QEMU VM into a
  distributable libvirt-format box. The box disk is flattened from its qcow2
  overlay into a standalone qcow2 with `qemu-img convert` (the live VM disk is
  never modified). A single-disk VM produces `box.img`; a multi-disk VM
  produces `box_1.img`..`box_N.img` plus a `disks[]` entry in `metadata.json`.
  `metadata.json` is written with `provider: libvirt` / `format: qcow2` /
  `virtual_size`, and a minimal default Vagrantfile declaring the box `arch` is
  bundled. `--output`/`--include`/`--info`/`--vagrantfile` are handled by the
  core packaging middleware. Environment-specific state — networking, MAC,
  additional disks, DVDs/cloud-init seed ISOs, and firmware — is intentionally
  not baked into the box.

# 0.6.0 (2026-07-21)

* `net_mode = :socket_vmnet` adds no-sudo private networking on macOS: the
  [socket_vmnet](https://github.com/lima-vm/socket_vmnet) daemon holds the root
  vmnet membership and QEMU connects to it as a normal user, so `vagrant up`
  and the other lifecycle commands need no sudo. It reuses the advanced-network
  dual-NIC + cloud-init path — NIC 0 user-mode (SSH + port forwarding), NIC 1
  on socket_vmnet with the configured static IP — giving host↔VM and VM↔VM
  connectivity. On QEMU >= 7.2 QEMU connects to the daemon directly
  (`-netdev stream`); on older QEMU it falls back to the `socket_vmnet_client`
  wrapper (`-netdev socket,fd=3`), chosen automatically by probing the QEMU
  binary. New config: `socket_vmnet_socket` and `socket_vmnet_client` (default
  to the Homebrew prefix). The static IP must fall within the daemon's subnet
  (`--vmnet-gateway`, default `192.168.105.1/24`); see the README. (#41)

# 0.6.1 (2026-07-22)

* Fix `vagrant reload` (and any other same-process halt-then-start, e.g. the
  `vagrant-reload` plugin) failing with a QEMU image write-lock error when a
  custom disk (`config.vm.disk`) was configured. `configure_disks` re-runs on
  every `action_start`, but the driver's attached-disk list only ever
  accumulated, so a reload attached each custom disk twice on the same qemu
  command line. (#41)
* Fix `qemu-img create` unconditionally recreating an already-existing custom
  disk on every `configure_disks` call, which silently wiped the disk's
  contents on every reload (independent of the bug above — resizing an
  existing disk to a new configured size still isn't supported).
* Fix the cloud-init network seed ISO (used by `advanced_network` without a
  core `cloud_init` user-data config, i.e. the `net_mode` examples above)
  being re-registered as a duplicate disk on every same-process reload,
  hitting the same QEMU write-lock error via a different disk.

# 0.6.2 (2026-07-22)

* Fix the default QEMU args crashing the VM on distros whose qemu-kvm build
  doesn't include the legacy parallel port device (e.g. Rocky Linux, and
  likely RHEL and other derivatives). `-parallel null` still instantiates
  that device, just with its output discarded; `-parallel none` — now the
  default — skips creating it entirely, matching how the other default args
  (`-monitor`/`-display`/`-vga`) already disable their optional devices. (#80)

# 0.6.3 (2026-08-12)

* Fix `vagrant up` aborting with `no implicit conversion of nil into Array`
  on macOS whenever `advanced_network` was enabled without also setting
  `net_mode`. The default `net_mode` of `:auto` selects the vmnet backend but
  was never resolved to a concrete mode, so the backend produced no `-netdev`
  arguments for the private network NIC and the command line assembly blew up
  before QEMU was launched. Setting `net_mode` explicitly (e.g.
  `:vmnet_shared`) was the workaround. (#40)

# 0.6.4 (2026-10-09)

* Fix `vagrant up` failing with `ForwardPortCollision` ("The forwarded port
  to 50022 is already in use") on macOS 27 even when nothing listens on the
  port. A non-blocking connect to a closed local port there reports success
  on the retry, so Vagrant's port check treated every port as in use. The
  provider now supplies a port check that confirms the connection; results on
  other systems are unchanged, and Windows keeps Vagrant's own check.
* Quote MAC addresses in the generated cloud-init `network-config`. cloud-init
  reads it as YAML 1.1, where an unquoted MAC whose octets are all decimal and
  below 60 (e.g. `52:54:00:26:47:05`) is a base-60 integer. With
  `advanced_network`, about 1.3% of generated MACs hit this, and the guest's
  network config was rejected, which could leave the VM unreachable over SSH
  on first boot. (#82, thanks @SamuelBoerlin)
* README: bring a `socket_opts` `listen=`/`connect=` pair up with
  `vagrant up --no-parallel`. A plain `vagrant up` boots both machines in
  parallel, and if the connector starts first the link never comes up.

# 0.7.0 (2026-10-15)

Thanks to @christhomas, who contributed most of this release
(#81, #85, #87–#95).

New:

* VirtioFS synced folders: `config.vm.synced_folder ..., type: "qemu_virtiofs"`.
  The provider starts one `virtiofsd` per share, backs guest RAM with a shared
  memory file and mounts the shares after boot; the daemons are stopped on
  halt, destroy, package and failed boots. New config: `virtiofsd_bin`,
  `virtiofs_guest_uid` / `virtiofs_guest_gid` (default 1000) and
  `extra_virtiofsd_args`; `qe.memory` must be a positive size. Linux hosts and
  WSL2 use the distribution's `virtiofsd`. macOS support is experimental and
  needs a QEMU built with vhost-user and a macOS `virtiofsd` port, available
  from a community Homebrew tap (see the README). (#81)
* `vagrant serial-config [name|id] [--json]` prints the Unix socket path or TCP
  host and port of each QEMU machine's serial console. (#37, #92)
* README: how to package a QEMU machine into a reusable box, plus a tested
  round-trip recipe in `examples/package-roundtrip`. (#94)

Behavior changes:

* If the guest does not become reachable within `config.vm.boot_timeout`
  (default 300 s), or Vagrant reports an invalid boot state, the provider now
  stops the QEMU instance it just started and keeps its disks. Previously QEMU
  was left running. Emulated guests (a guest architecture different from the
  host, or no HVF/KVM) and several VMs booting in parallel can need more than
  300 s; set `config.vm.boot_timeout = 600` or more. A guest that used to
  finish booting in the background after the timeout now has to be brought up
  again with `vagrant up`, from the start. Interrupting the boot wait with
  Ctrl-C still leaves QEMU running. (#89, refs #21)
* `config.vm.disk :disk, primary: true, size: ...` now grows the existing boot
  disk instead of attaching a new blank disk; it never shrinks it, and reports
  sizes such as `100 GiB`. The blank disk an older version created for the
  declaration (`vagrant_primary.qcow2`, or `<name>.qcow2` for a custom name)
  is no longer attached; the provider warns while that file exists, and
  the README's "Upgrading older primary disk declarations" section shows how to
  attach it again. (#66, #88, #93, #95)
* With `net_device = nil`, an inherited SSH forward is disabled and the
  configured `ssh_port` is kept instead of a collision-corrected one. (#71, #87)

Fixes:

* macOS: firmware for an aarch64 guest is now looked up in the host's Homebrew
  prefix rather than one chosen by the guest architecture, fixing Intel Macs.
  If Vagrant's Ruby runs under Rosetta on Apple Silicon, set `HOMEBREW_PREFIX`
  or `qe.qemu_dir`. (#50, #59, #90)
* Waiting for a monitor reply during `vagrant halt` is now bounded, so halt can
  always escalate to quit and kill. With `control_port` set, halt connects to
  127.0.0.1: on macOS 27 connecting to localhost could pick ::1 and appear
  connected, so powerdown and quit were never delivered and QEMU was killed
  only after both timeouts. (#89)
* `vagrant halt` could fail with `Errno::ENOENT` when QEMU removed its pidfile
  just as the provider read it. An empty pidfile no longer reads as a running
  VM, and a force kill waits for QEMU to exit.
* Updating the SSH forward no longer leaks into other machines that share a
  forwarded_port rule from the top-level or box Vagrantfile.
* README: AlmaLinux 9 x86_64 guests need `qe.cpu = "max"` under emulation
  (#67, #91); the `other_default` default is `-parallel none`.

Project:

* Cross-platform CI on GitHub Actions: unit specs on Linux, macOS and Windows;
  guest smoke tests on Linux, macOS and WSL2; e2e on Linux (KVM), macOS (TCG:
  vmnet, socket_vmnet, VirtioFS) and VirtioFS in WSL2. (#85)
* The gem now ships only `lib/`, `locales/`, `LICENSE`, `README.md` and
  `CHANGELOG.md`.
