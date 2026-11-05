#!/bin/bash
# QEMU twin: rootfs.ext4 is used directly as /dev/vda, data.ext4 as /dev/vdb.
set -euo pipefail
BOARD_DIR="$(dirname "$0")"
rm -f "${BINARIES_DIR}/data.ext4"
"${HOST_DIR}/sbin/mkfs.ext4" -q -F -L data "${BINARIES_DIR}/data.ext4" 200M
cp "${BOARD_DIR}/../common/rpi-player.conf" "${BINARIES_DIR}/rpi-player.conf"
