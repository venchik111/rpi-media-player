#!/bin/bash
# Assemble sdcard.img: boot (FAT) + rootfs (ext4) + data (ext4, empty).
set -euo pipefail

BOARD_DIR="$(dirname "$0")"
COMMON_DIR="${BOARD_DIR}/../common"
GENIMAGE_CFG="${BINARIES_DIR}/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# User-editable config lives on the FAT partition (editable from any PC).
cp "${COMMON_DIR}/rpi-player.conf" "${BINARIES_DIR}/rpi-player.conf"

FILES=()
for i in "${BINARIES_DIR}"/*.dtb "${BINARIES_DIR}"/rpi-firmware/*; do
	FILES+=( "${i#"${BINARIES_DIR}"/}" )
done
KERNEL=$(sed -n 's/^kernel=//p' "${BINARIES_DIR}/rpi-firmware/config.txt")
FILES+=( "${KERNEL}" "rpi-player.conf" )

BOOT_FILES=$(printf '\t\t\t"%s",\n' "${FILES[@]}")
sed "s|#BOOT_FILES#|${BOOT_FILES}|" "${BOARD_DIR}/genimage.cfg.in" > "${GENIMAGE_CFG}"

# Empty data partition (media files, ssh host keys).
rm -f "${BINARIES_DIR}/data.ext4"
"${HOST_DIR}/sbin/mkfs.ext4" -q -F -L data "${BINARIES_DIR}/data.ext4" 200M

trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
ROOTPATH_TMP="$(mktemp -d)"
rm -rf "${GENIMAGE_TMP}"

genimage \
	--rootpath "${ROOTPATH_TMP}" \
	--tmppath "${GENIMAGE_TMP}" \
	--inputpath "${BINARIES_DIR}" \
	--outputpath "${BINARIES_DIR}" \
	--config "${GENIMAGE_CFG}"

SIZE=$(stat -c %s "${BINARIES_DIR}/sdcard.img")
LIMIT=$((500 * 1024 * 1024))
echo "sdcard.img: $((SIZE / 1024 / 1024)) MiB (limit $((LIMIT / 1024 / 1024)) MiB)"
if [ "${SIZE}" -gt "${LIMIT}" ]; then
	echo "ERROR: image does not fit a 512 MB card" >&2
	exit 1
fi
