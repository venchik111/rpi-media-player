#!/bin/bash
# Static checks of out/rpi4/sdcard.img for everything QEMU cannot exercise:
# partition table, Pi boot files, Wi-Fi firmware, kernel modules matching the
# kernel, regulatory DB, services and their exec bits. Exit 1 on any failure.
set -uo pipefail
cd "$(dirname "$0")/.."
IMG="${1:-out/rpi4/sdcard.img}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FAIL=0
ok()   { printf '  \e[32mOK\e[0m   %s\n' "$*"; }
bad()  { printf '  \e[31mFAIL\e[0m %s\n' "$*"; FAIL=1; }
warn() { printf '  \e[33mWARN\e[0m %s\n' "$*"; }
check() { local msg=$1; shift; if "$@" >/dev/null 2>&1; then ok "$msg"; else bad "$msg"; fi; }

echo "== image: $IMG"
[ -f "$IMG" ] || { bad "image missing"; exit 1; }
SIZE=$(stat -c %s "$IMG")
[ "$SIZE" -le $((500 * 1024 * 1024)) ] && ok "size $((SIZE / 1048576)) MiB <= 500 MiB (fits 512 MB card)" || bad "size $((SIZE / 1048576)) MiB"

echo "== partitions"
sfdisk -d "$IMG" > "$T/pt" 2>/dev/null || bad "no partition table"
mapfile -t PARTS < <(grep -E "^$IMG" "$T/pt")
[ "${#PARTS[@]}" -eq 3 ] && ok "3 partitions" || bad "expected 3 partitions, got ${#PARTS[@]}"
part() { # $1 = index (1-based) -> "start size type"
	sed -n "${1}p" < <(printf '%s\n' "${PARTS[@]}") | sed -E 's/.*start= *([0-9]+), size= *([0-9]+), type=([0-9a-fA-F]+).*/\1 \2 \3/'
}
read -r S1 N1 TY1 <<<"$(part 1)"; read -r S2 N2 TY2 <<<"$(part 2)"; read -r S3 N3 TY3 <<<"$(part 3)"
[ "$TY1" = c ] && grep -q "bootable" <<<"${PARTS[0]}" && ok "p1 FAT32 LBA, bootable" || bad "p1 type=$TY1 (want c, bootable)"
[ "$TY2" = 83 ] && ok "p2 Linux (rootfs)" || bad "p2 type=$TY2"
[ "$TY3" = 83 ] && ok "p3 Linux (data)" || bad "p3 type=$TY3"
dd if="$IMG" of="$T/boot.vfat" bs=512 skip="$S1" count="$N1" status=none
dd if="$IMG" of="$T/rootfs.ext4" bs=512 skip="$S2" count="$N2" status=none
dd if="$IMG" of="$T/data.ext4" bs=512 skip="$S3" count="$N3" status=none
check "p3 is ext4 labelled 'data'" bash -c "dumpe2fs -h '$T/data.ext4' 2>/dev/null | grep -q 'volume name: *data$'"

echo "== BOOT partition"
mlabel -i "$T/boot.vfat" -s :: 2>/dev/null | grep -q BOOT && ok "FAT label BOOT" || bad "FAT label is not BOOT"
mdir -i "$T/boot.vfat" -b -/ :: > "$T/bootfiles" 2>/dev/null
for f in start4.elf fixup4.dat config.txt cmdline.txt Image bcm2711-rpi-4-b.dtb rpi-player.conf overlays/miniuart-bt.dtbo; do
	grep -q "::/$f$" "$T/bootfiles" && ok "$f" || bad "missing $f"
done
mtype -i "$T/boot.vfat" ::config.txt > "$T/config.txt" 2>/dev/null
mtype -i "$T/boot.vfat" ::cmdline.txt > "$T/cmdline.txt" 2>/dev/null
check "config.txt: arm_64bit=1" grep -qx 'arm_64bit=1' "$T/config.txt"
check "config.txt: kernel=Image" grep -qx 'kernel=Image' "$T/config.txt"
check "cmdline.txt: root=/dev/mmcblk0p2 rootwait" grep -q 'root=/dev/mmcblk0p2 rootwait' "$T/cmdline.txt"
[ "$(wc -l < "$T/cmdline.txt")" -le 1 ] && ok "cmdline.txt is a single line" || bad "cmdline.txt has several lines"
mtype -i "$T/boot.vfat" ::rpi-player.conf > "$T/rpi-player.conf" 2>/dev/null
check "rpi-player.conf parses as shell" sh -n "$T/rpi-player.conf"
mcopy -i "$T/boot.vfat" ::Image "$T/Image" 2>/dev/null
KVER_IMG=$(strings "$T/Image" | sed -n 's/^Linux version \([^ ]*\).*/\1/p' | head -n1)
[ -n "$KVER_IMG" ] && ok "kernel version $KVER_IMG" || bad "cannot read kernel version from Image"

echo "== rootfs"
dbg() { debugfs -R "$1" "$T/rootfs.ext4" 2>/dev/null; }
exists() { dbg "stat $1" | grep -q 'Inode:'; }
KDIR=$(dbg "ls -p /lib/modules" | awk -F/ '$6 !~ /^\.\.?$/ && $6 != "" {print $6}' | head -n1)
[ "$KDIR" = "$KVER_IMG" ] && ok "/lib/modules/$KDIR matches kernel" || bad "modules dir '$KDIR' != kernel '$KVER_IMG'"
dbg "dump /lib/modules/$KDIR/modules.dep $T/modules.dep" >/dev/null
dbg "dump /lib/modules/$KDIR/modules.alias $T/modules.alias" >/dev/null
for m in brcmfmac brcmutil cfg80211; do
	grep -qE "/$m\.ko(\.xz|\.gz|\.zst)?:" "$T/modules.dep" && ok "module $m" || bad "module $m missing"
done
grep -q 'sdio:c\*v02D0d4345' "$T/modules.alias" && ok "brcmfmac SDIO alias for BCM43455 (autoload)" || bad "no SDIO alias for BCM43455"
grep -qE '/bcm2835-codec\.ko' "$T/modules.dep" && ok "bcm2835-codec (HW H.264 encoder)" || warn "bcm2835-codec missing: transcoding falls back to libx264"

dbg "ls -p /lib/firmware/brcm" | awk -F/ '{print $6}' > "$T/fw"
for f in brcmfmac43455-sdio.bin brcmfmac43455-sdio.clm_blob; do
	grep -qx "$f" "$T/fw" && ok "firmware $f" || bad "firmware $f missing"
done
grep -qE '^brcmfmac43455-sdio\.(raspberrypi,4-model-b\.txt|txt)$' "$T/fw" && ok "firmware NVRAM for Pi 4B" || bad "firmware NVRAM (.txt) for 43455 missing"
check "regulatory.db" exists /lib/firmware/regulatory.db

for b in /usr/sbin/hostapd /usr/sbin/dnsmasq /usr/sbin/sshd /usr/bin/ffmpeg /usr/bin/ffprobe \
	/usr/sbin/lighttpd /usr/lib/lighttpd/mod_setenv.so /usr/bin/ssh-keygen /usr/sbin/iw /sbin/fsck.ext4; do
	check "$b" exists "$b"
done
for s in S01storage S20modules S41eth0 S42wifi-ap S43dnsmasq S44sshd S60httpd S70player; do
	mode=$(dbg "stat /etc/init.d/$s" | sed -n 's/.*Mode: *\([0-7]*\).*/\1/p')
	[ "${mode: -3}" = 755 ] && ok "init.d/$s executable" || bad "init.d/$s mode=$mode"
done
for s in S50sshd S50lighttpd S80dnsmasq; do
	exists "/etc/init.d/$s" && bad "stale package init script $s present" || true
done
check "/etc/rpi-player.conf.default" exists /etc/rpi-player.conf.default
check "/etc/modules loads brcmfmac" bash -c "debugfs -R 'cat /etc/modules' '$T/rootfs.ext4' 2>/dev/null | grep -qx brcmfmac"
check "user 'media' exists" bash -c "debugfs -R 'cat /etc/passwd' '$T/rootfs.ext4' 2>/dev/null | grep -q '^media:'"
check "inittab: serial console" bash -c "debugfs -R 'cat /etc/inittab' '$T/rootfs.ext4' 2>/dev/null | grep -q getty"

echo
if [ "$FAIL" = 0 ]; then echo "AUDIT PASSED"; else echo "AUDIT FAILED"; exit 1; fi
