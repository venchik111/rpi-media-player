#!/bin/bash
# Build an image inside the builder container.
#   scripts/build.sh rpi4    -> out/rpi4/sdcard.img
#   scripts/build.sh qemu    -> out/qemu/{Image,rootfs.ext4,data.ext4}
# Extra args go to make, e.g. "scripts/build.sh rpi4 menuconfig".
set -euo pipefail

TARGET="${1:-rpi4}"; shift || true
SRC="${SRC:-/src}"            # repo (read from here)
WORK="${WORK:-/work}"         # fast Linux FS: buildroot tree, output, dl cache
BR="$WORK/buildroot"
EXT="$WORK/br2-external"
OUT="$WORK/output-$TARGET"

case "$TARGET" in rpi4|qemu) ;; *) echo "unknown target: $TARGET" >&2; exit 1 ;; esac

# Buildroot checkout on a real Linux FS (the Windows checkout breaks symlinks).
REV=$(git -C "$SRC/buildroot" rev-parse HEAD)
if [ ! -d "$BR/.git" ]; then
	git -c init.defaultBranch=main clone -q --no-checkout "$SRC/buildroot" "$BR"
fi
if [ "$(git -C "$BR" rev-parse HEAD 2>/dev/null || true)" != "$REV" ]; then
	git -C "$BR" fetch -q "$SRC/buildroot" "$REV"
	git -C "$BR" reset -q --hard "$REV"
fi
if [ ! -f "$BR/Makefile" ]; then
	git -C "$BR" reset -q --hard "$REV"
fi

# Our tree: normalise line endings / exec bits that a Windows checkout may mangle.
rsync -a --delete "$SRC/br2-external/" "$EXT/"
find "$EXT" -type f \( -name '*.sh' -o -path '*/init.d/*' -o -path '*/libexec/*' -o -path '*/sbin/*' \) \
	-exec sed -i 's/\r$//' {} + -exec chmod 0755 {} +

# Raspberry Pi boot firmware: only boot/ files, via sparse blob-filtered git
# (see br2-external/board/rpi4/local.mk). Version = the one Buildroot pins.
if [ "$TARGET" = rpi4 ]; then
	FW_REV=$(sed -n 's/^RPI_FIRMWARE_VERSION = //p' "$BR/package/rpi-firmware/rpi-firmware.mk")
	FW_DIR="${BR2_DL_DIR:-$WORK/dl}/rpi-firmware-sparse"
	if [ "$(git -C "$FW_DIR" rev-parse HEAD 2>/dev/null || true)" != "$FW_REV" ]; then
		rm -rf "$FW_DIR"
		git -c init.defaultBranch=main init -q "$FW_DIR"
		git -C "$FW_DIR" remote add origin https://github.com/raspberrypi/firmware.git
		git -C "$FW_DIR" sparse-checkout set --no-cone \
			'/boot/*.elf' '/boot/*.dat' '/boot/bootcode.bin' '/boot/overlays/' '/boot/LICENCE.broadcom'
		git -C "$FW_DIR" fetch -q --depth 1 --filter=blob:none origin "$FW_REV"
		git -C "$FW_DIR" -c advice.detachedHead=false checkout -q FETCH_HEAD
	fi
fi

if [ ! -f "$OUT/.config" ] || [ "$EXT/configs/${TARGET}_player_defconfig" -nt "$OUT/.config" ]; then
	make -C "$BR" O="$OUT" BR2_EXTERNAL="$EXT" "${TARGET}_player_defconfig"
fi

make -C "$OUT" "$@"

if [ $# -eq 0 ]; then
	mkdir -p "$SRC/out/$TARGET"
	case "$TARGET" in
		rpi4) cp "$OUT"/images/{sdcard.img,Image,bcm2711-rpi-4-b.dtb,boot.vfat,rootfs.ext4,data.ext4} "$SRC/out/$TARGET/" ;;
		qemu) cp "$OUT"/images/{Image,rootfs.ext4,data.ext4} "$SRC/out/$TARGET/" ;;
	esac
	du -h "$SRC/out/$TARGET"/*
fi
