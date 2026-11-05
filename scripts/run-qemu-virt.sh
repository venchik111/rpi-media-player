#!/bin/bash
# Boot the QEMU 'virt' twin (out/qemu). Ports on the host:
#   localhost:2222 -> ssh/sftp, localhost:8080 -> HLS
# Env: FRESH=1 reset disks, SERIAL=<qemu -serial arg>, SSH_PORT, HTTP_PORT.
# Quit the console with Ctrl-A X.
set -euo pipefail
cd "$(dirname "$0")/.."
IMG=out/qemu
RUN="${RUN_DIR:-/work/qemu-run}"
mkdir -p "$RUN"
for f in rootfs.ext4 data.ext4; do
	if [ "${FRESH:-0}" = 1 ] || [ ! -f "$RUN/$f" ] || [ "$IMG/$f" -nt "$RUN/$f" ]; then
		cp "$IMG/$f" "$RUN/$f"
	fi
done

exec qemu-system-aarch64 \
	-M virt -cpu cortex-a72 -smp 4 -m 1024 \
	-kernel "$IMG/Image" \
	-append "rootwait root=/dev/vda console=ttyAMA0" \
	-drive file="$RUN/rootfs.ext4",if=none,format=raw,id=root -device virtio-blk-device,drive=root \
	-drive file="$RUN/data.ext4",if=none,format=raw,id=data -device virtio-blk-device,drive=data \
	-netdev user,id=eth0,hostfwd=tcp::"${SSH_PORT:-2222}"-:22,hostfwd=tcp::"${HTTP_PORT:-8080}"-:8080 \
	-device virtio-net-device,netdev=eth0 \
	-nographic -serial "${SERIAL:-mon:stdio}" ${QEMU_EXTRA:-}
