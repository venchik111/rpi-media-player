#!/bin/bash
# Boot on QEMU 'virt' with simulated Wi-Fi (mac80211_hwsim, built into the kernel).
#
#   ROOTFS=pi   (default) the exact rootfs + BOOT + data partitions from the
#               Raspberry Pi image (out/rpi4), on the QEMU kernel (out/qemu/Image).
#               Tests what ships on the SD card, minus Pi kernel/Wi-Fi driver.
#   ROOTFS=qemu the QEMU twin's own rootfs (out/qemu).
#
# Host ports: localhost:2222 -> ssh/sftp, localhost:8080 -> HLS.
# Env: FRESH=1 reset disks, SERIAL=<qemu -serial arg>, SSH_PORT, HTTP_PORT.
# Quit the console with Ctrl-A X.
set -euo pipefail
cd "$(dirname "$0")/.."
KERNEL=out/qemu/Image
case "${ROOTFS:-pi}" in
	pi) IMG=out/rpi4; DISKS="rootfs.ext4 data.ext4 boot.vfat" ;;
	qemu) IMG=out/qemu; DISKS="rootfs.ext4 data.ext4" ;;
	*) echo "ROOTFS must be pi or qemu" >&2; exit 1 ;;
esac
RUN="${RUN_DIR:-/work/qemu-run}/${ROOTFS:-pi}"
mkdir -p "$RUN"
DRIVES=()
for f in $DISKS; do
	if [ "${FRESH:-0}" = 1 ] || [ ! -f "$RUN/$f" ] || [ "$IMG/$f" -nt "$RUN/$f" ]; then
		cp "$IMG/$f" "$RUN/$f"
	fi
	id="${f%%.*}"
	# vda=rootfs, vdb=data, vdc=BOOT (order matters, see S01storage)
	DRIVES+=(-drive "file=$RUN/$f,if=none,format=raw,id=$id" -device "virtio-blk-pci,drive=$id")
done

exec qemu-system-aarch64 \
	-M virt -cpu cortex-a72 -smp 4 -m 1024 \
	-kernel "$KERNEL" \
	-append "rootwait root=/dev/vda console=ttyAMA0" \
	"${DRIVES[@]}" \
	-netdev user,id=eth0,hostfwd=tcp::"${SSH_PORT:-2222}"-:22,hostfwd=tcp::"${HTTP_PORT:-8080}"-:8080 \
	-device virtio-net-pci,netdev=eth0,romfile= \
	-nographic -serial "${SERIAL:-mon:stdio}" ${QEMU_EXTRA:-}
