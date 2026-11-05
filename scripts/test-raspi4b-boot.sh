#!/bin/bash
# Boot out/rpi4/sdcard.img (real Pi kernel + DTB + rootfs) on QEMU raspi4b and
# check the serial log: kernel up, partitions mounted, services started.
# QEMU's raspi4b has no Wi-Fi/Ethernet, so "no wlan0" is expected there.
set -uo pipefail
cd "$(dirname "$0")/.."
LOG="${RUN_DIR:-/work/qemu-run}/raspi4b-serial.log"
mkdir -p "$(dirname "$LOG")"; rm -f "$LOG"
TIMEOUT="${TIMEOUT:-420}"

SERIAL="file:$LOG" timeout "$TIMEOUT" scripts/run-qemu-raspi4b.sh </dev/null >/dev/null 2>&1 &
QPID=$!
end=$((SECONDS + TIMEOUT))
until grep -q 'login:' "$LOG" 2>/dev/null || [ $SECONDS -ge $end ] || ! kill -0 $QPID 2>/dev/null; do
	sleep 3
done
sleep 5   # let late init output land
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null

FAIL=0
expect() { if grep -qE "$2" "$LOG"; then echo "  OK   $1"; else echo "  FAIL $1"; FAIL=1; fi; }
reject() { if grep -qE "$2" "$LOG"; then echo "  FAIL $1"; grep -E "$2" "$LOG" | head -3; FAIL=1; else echo "  OK   $1"; fi; }

echo "== raspi4b boot log checks ($LOG)"
expect "Pi kernel booted with BCM2711 DTB"   'Machine model: Raspberry Pi 4 Model B'
expect "root filesystem mounted"            'EXT4-fs \(mmcblk[01]p2\): mounted'
expect "BOOT + data partitions mounted"     'rpi-player: storage ready \(boot=/dev/mmcblk[01]p1 data=/dev/mmcblk[01]p3\)'
expect "reached login prompt"               'login:'
reject "kernel panic"                       'Kernel panic|Oops|BUG:'
reject "init script errors"                 'not found|Permission denied|syntax error|can.t open'
echo "(expected on QEMU: 'no wlan0 interface' -> $(grep -c 'no wlan0' "$LOG") line)"
if [ $FAIL = 0 ]; then echo "RASPI4B BOOT PASSED"; else echo "RASPI4B BOOT FAILED"; tail -40 "$LOG"; exit 1; fi
