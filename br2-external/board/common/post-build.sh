#!/bin/sh
# $1 = board name (rpi4 | qemu), from BR2_ROOTFS_POST_SCRIPT_ARGS
set -eu
BOARD="${1:-rpi4}"
T="${TARGET_DIR}"
COMMON_DIR="$(dirname "$0")"

# Package init scripts are replaced by ours (S44sshd, S60httpd, S43dnsmasq).
# Ours must not reuse these names, or they would be deleted here too.
rm -f "$T/etc/init.d/S50sshd" "$T/etc/init.d/S50lighttpd" "$T/etc/init.d/S80dnsmasq"

# Files coming from a Windows checkout may lose the exec bit.
chmod 0755 "$T"/etc/init.d/S* "$T"/usr/sbin/player-ctl "$T"/usr/libexec/rpi-player/* 2>/dev/null || true

# Built-in default config (used when /boot/rpi-player.conf is missing).
install -D -m 0644 "$COMMON_DIR/rpi-player.conf" "$T/etc/rpi-player.conf.default"

echo "$BOARD" > "$T/etc/rpi-player.board"

# Lower bound for the clock on boards without a battery-backed RTC (see S01storage).
date +%s > "$T/etc/rpi-player.buildtime"

# Mount points
mkdir -p "$T/boot" "$T/data"

# Serial console only; add HDMI console on the Pi.
if [ "$BOARD" = "rpi4" ] && ! grep -q '^tty1::' "$T/etc/inittab"; then
	sed -i '/GENERIC_SERIAL/a\
tty1::respawn:/sbin/getty -L  tty1 0 vt100 # HDMI console' "$T/etc/inittab"
fi
