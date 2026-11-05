#!/bin/bash
# Boot the real Raspberry Pi image (out/rpi4/sdcard.img) on QEMU's raspi4b board.
# Upstream QEMU has no PCIe/USB/Ethernet for raspi4b and no Wi-Fi chip, so this
# only proves that kernel, DTB, partitions and services come up.
# Env: SERIAL, ROOT (default /dev/mmcblk1p2 - QEMU exposes the SD as mmcblk1).
set -euo pipefail
cd "$(dirname "$0")/.."
IMG=out/rpi4
RUN="${RUN_DIR:-/work/qemu-run}"
mkdir -p "$RUN"
# QEMU needs an SD image whose size is a power of two.
cp "$IMG/sdcard.img" "$RUN/sd-raspi4b.img"
qemu-img resize -q -f raw "$RUN/sd-raspi4b.img" 512M

exec qemu-system-aarch64 \
	-M raspi4b -m 2G \
	-kernel "$IMG/Image" -dtb "$IMG/bcm2711-rpi-4-b.dtb" \
	-drive file="$RUN/sd-raspi4b.img",if=sd,format=raw \
	-append "root=${ROOT:-/dev/mmcblk1p2} rootwait console=ttyAMA0,115200" \
	-nographic -serial "${SERIAL:-mon:stdio}" ${QEMU_EXTRA:-}
