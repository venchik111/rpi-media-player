#!/bin/bash
# Makes out/rpi4/sdcard-debug.img: the normal image with DIAG_LOG="yes" in BOOT.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=out/rpi4/sdcard.img; DST=out/rpi4/sdcard-debug.img
cp "$SRC" "$DST"
START=$(sfdisk -d "$DST" | sed -n 's/.*sdcard-debug.img1 : start= *\([0-9]*\),.*/\1/p')
FAT="$DST@@$((START * 512))"
T=$(mktemp)
mtype -i "$FAT" ::rpi-player.conf | sed 's/^DIAG_LOG=.*/DIAG_LOG="yes"/' > "$T"
grep -qx 'DIAG_LOG="yes"' "$T"
mcopy -o -i "$FAT" "$T" ::rpi-player.conf
rm -f "$T"
ls -la "$DST"
