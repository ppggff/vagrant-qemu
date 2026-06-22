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
