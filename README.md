# rpi-media-player

Minimal Linux image for **Raspberry Pi 4B** (fits a 512 MB card) that acts as a
Wi-Fi **IP webcam**: it brings up its own access point and streams an uploaded
video as an endless live **HLS** stream. Files are uploaded over **SFTP**.

```
phone/laptop ──Wi-Fi "rpi-cam"──▶ Pi 4B ──▶ http://192.168.50.1:8080/stream.m3u8
                                   ▲
                    sftp media@192.168.50.1  (upload video)
```

## How it works
| Piece | Implementation |
|---|---|
| OS | Buildroot 2026.02.3 (LTS), BusyBox init, glibc, RPi kernel |
| Access point | hostapd (`wlan0`, brcmfmac) + dnsmasq DHCP, params from `rpi-player.conf` |
| SSH / SFTP | OpenSSH, `internal-sftp`, full file-system access, host keys kept on `/data` |
| Stream | `player-ctl`: ffmpeg loops the newest file in `/data/media` into a live HLS window (`-c copy` for H.264, one-off transcode otherwise), lighttpd on :8080 |
| No video yet | "no signal" SMPTE bars (or your own `/data/media/placeholder.jpg`) |

SD card layout (`sdcard.img`, ~470 MB): `BOOT` FAT 64 MB (firmware, kernel, **`rpi-player.conf`**),
`rootfs` ext4 200 MB, `data` ext4 200 MB (`/data/media`, ssh keys).

## Configuration
Edit `rpi-player.conf` on the FAT partition from any PC (or `/boot/rpi-player.conf`
on the device, remount rw first). SSID, passphrase, country, channel, addresses,
HLS port/segment size, file to play, passwords. Defaults:

| | |
|---|---|
| SSID / passphrase | `rpi-cam` / `camera1234` |
| Stream | `http://192.168.50.1:8080/stream.m3u8` (also `/` — web page with a player) |
| SSH/SFTP | `root` / `player`, `media` / `media` (change them!) |

## Build (Windows with Docker Desktop, or Linux)
```bash
git clone --recurse-submodules https://github.com/venchik111/rpi-media-player
cd rpi-media-player
scripts/docker.sh scripts/build.sh rpi4     # -> out/rpi4/sdcard.img
scripts/docker.sh scripts/build.sh qemu     # -> out/qemu/ (test twin)
```
First build takes 1–2 h (toolchain, kernel, ffmpeg); downloads and ccache live in
the `rpi-player-work` Docker volume, so rebuilds are fast.

Flash `out/rpi4/sdcard.img` with Raspberry Pi Imager ("Use custom") or `dd`.

## Upload and watch
```bash
sftp media@192.168.50.1        # put movie.mp4
vlc http://192.168.50.1:8080/stream.m3u8
```
The newest upload starts playing automatically (inotify). Set `MEDIA_FILE` in the
config, or a `current` symlink in `/data/media`, to pin a file. `player-ctl status`
shows what is streaming.

## Testing without hardware
Upstream QEMU has a `raspi4b` board, but **no PCIe/USB/Ethernet and no Wi-Fi** for it
(PCIe+GENET patches are still under review). So testing has two levels:

1. **QEMU `virt` twin** (`qemu_player_defconfig`) — same overlay and packages, upstream
   kernel with `mac80211_hwsim` (two simulated radios: one is our AP, the other a test
   client in a separate network namespace). Full end-to-end suite:
   ```bash
   scripts/docker.sh scripts/test.sh
   ```
   Interactive: `DOCKER_ARGS="-p 2222:2222 -p 8080:8080" scripts/docker.sh scripts/run-qemu-virt.sh`,
   then `ssh -p 2222 root@localhost`, `vlc http://localhost:8080/stream.m3u8`.
2. **QEMU `raspi4b`** — boots the real `sdcard.img` (kernel, DTB, partitions, init):
   ```bash
   scripts/docker.sh scripts/run-qemu-raspi4b.sh
   ```
3. Real Pi 4B — Wi-Fi chip, hardware H.264 encoder, timings.

## Layout
```
buildroot/            Buildroot submodule (pinned)
br2-external/         our Buildroot tree: defconfigs, board files, rootfs overlay
docker/Dockerfile     build + QEMU + test environment
scripts/              build.sh, docker.sh, run-qemu-*.sh, test.sh
tests/                pytest end-to-end tests (run against QEMU virt)
```
