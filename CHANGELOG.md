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
