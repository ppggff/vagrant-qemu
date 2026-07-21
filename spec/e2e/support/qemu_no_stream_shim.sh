#!/usr/bin/env bash
# Test shim: forces vagrant-qemu's socket_vmnet backend down the wrapper route
# on a modern QEMU by hiding the native `stream` netdev from the plugin's probe
# (`-M none -netdev help`). Every other invocation execs the real QEMU verbatim,
# so the fd 3 handed in by socket_vmnet_client is preserved into QEMU.
set -euo pipefail
REAL="${REAL_QEMU:-$(command -v qemu-system-aarch64 || true)}"
[ -x "$REAL" ] || REAL=/opt/homebrew/bin/qemu-system-aarch64

if [ "$*" = "-M none -netdev help" ]; then
  "$REAL" "$@" | grep -v '^stream$'
  exit 0
fi
exec "$REAL" "$@"
