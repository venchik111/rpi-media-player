#!/bin/bash
# Boot the real Raspberry Pi image (out/rpi4/sdcard.img) on QEMU's raspi4b board.
# Upstream QEMU has no PCIe/USB/Ethernet for raspi4b and no Wi-Fi chip, so this
# only proves that kernel, DTB, partitions and services come up.
#
# QEMU does not run the Pi boot firmware, so this script does its job: it applies
# the dtoverlay= lines of config.txt to the DTB (miniuart-bt puts the PL011 UART,
# i.e. ttyAMA0 = our console, on the GPIO header) and passes root= from cmdline.txt.
# Env: SERIAL, ROOT (default: root= from the image cmdline.txt).
set -euo pipefail
cd "$(dirname "$0")/.."
IMG=out/rpi4
RUN="${RUN_DIR:-/work/qemu-run}"
mkdir -p "$RUN"

# QEMU needs an SD image whose size is a power of two.
cp "$IMG/sdcard.img" "$RUN/sd-raspi4b.img"
qemu-img resize -q -f raw "$RUN/sd-raspi4b.img" 512M

# DTB with the overlays from config.txt applied (from the BOOT partition itself).
DTB="$RUN/bcm2711-rpi-4-b.qemu.dtb"
cp "$IMG/bcm2711-rpi-4-b.dtb" "$DTB"
mtype -i "$IMG/boot.vfat" ::config.txt | tr -d '\r' > "$RUN/config.txt"
for ovl in $(sed -n 's/^dtoverlay=\([^,]*\).*/\1/p' "$RUN/config.txt"); do
	mcopy -o -i "$IMG/boot.vfat" "::overlays/$ovl.dtbo" "$RUN/$ovl.dtbo"
	fdtoverlay -i "$DTB" -o "$DTB.new" "$RUN/$ovl.dtbo" && mv "$DTB.new" "$DTB"
	echo "applied overlay $ovl" >&2
done

IMAGE_ROOT=$(mtype -i "$IMG/boot.vfat" ::cmdline.txt | tr ' ' '\n' | sed -n 's/^root=//p')

exec qemu-system-aarch64 \
	-M raspi4b -m 2G \
	-kernel "$IMG/Image" -dtb "$DTB" \
	-drive file="$RUN/sd-raspi4b.img",if=sd,format=raw \
	-append "root=${ROOT:-$IMAGE_ROOT} rootwait console=ttyAMA0,115200" \
	-nographic -serial "${SERIAL:-mon:stdio}" ${QEMU_EXTRA:-}
