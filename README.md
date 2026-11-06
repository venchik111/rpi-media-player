# rpi-media-player

**[Документация на русском →](README.ru.md)**

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
| Stream | `player-ctl`: ffmpeg loops the newest file in `/data/media` into a live HLS window (`-c copy` for H.264 + AAC, one-off conversion otherwise; incomplete files are skipped), lighttpd on :8080 |
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
scripts/docker.sh scripts/build.sh qemu     # -> out/qemu/ (kernel for the virt tests)
```
First build takes 1–2 h (toolchain, kernel, ffmpeg); downloads and ccache live in
the `rpi-player-work` Docker volume, so rebuilds are fast.

Flash `out/rpi4/sdcard.img` with Raspberry Pi Imager ("Use custom") or `dd`.

### Bigger card = more room for video
The image works on any card >= 512 MB, but the `data` partition (videos) is a fixed
200 MB. On a bigger card, grow it to the end of the card after flashing, e.g. with
GParted (resize the last ext4 partition labelled `data`) or from a shell
(replace `sdX` with the card, double-check with `lsblk`):
```bash
sudo parted /dev/sdX resizepart 3 100%
```
```bash
sudo e2fsck -f /dev/sdX3 && sudo resize2fs /dev/sdX3
```
Videos and settings are kept. See [README.ru.md](README.ru.md) for a step-by-step guide.

## Upload and watch
```bash
sftp media@192.168.50.1        # put movie.mp4
vlc http://192.168.50.1:8080/stream.m3u8
```
The newest complete upload starts playing automatically (inotify). Older files are kept;
a failed or unreadable upload is skipped and the current video keeps playing. Prefer a new
file name: uploading under the same name overwrites the old clip. Set `MEDIA_FILE` in the
config, or a `current` symlink in `/data/media`, to pin a file. `player-ctl status`
shows what is streaming.

## Testing without hardware
No Raspberry Pi is needed to verify the image. `scripts/docker.sh scripts/test.sh` runs three
layers, each covering what the others cannot:

| Layer | What runs | Proves |
|---|---|---|
| `audit` | static checks of `sdcard.img` | partition table, size <= 500 MiB, Pi boot files (`start4.elf`, DTB, overlays, `config.txt`, `cmdline.txt`), **Wi-Fi firmware `brcmfmac43455`**, `brcmfmac` module + SDIO alias matching the kernel version, `regulatory.db`, binaries, init-script modes |
| `boot` | `sdcard.img` on **QEMU `raspi4b`** (Pi kernel + BCM2711 DTB) | the real kernel boots, root/BOOT/data partitions mount, all init scripts run, login prompt |
| `e2e` | the **exact Pi rootfs + BOOT + data partitions** on QEMU `virt` with `mac80211_hwsim` | config read from the FAT partition (CRLF edit), Wi-Fi AP comes up with that SSID/WPA2, a Wi-Fi client gets DHCP and the playlist, SFTP upload, live HLS that advances, H.264 + AAC segments, conversion of other formats, failed uploads do not disturb the stream |

Upstream QEMU `raspi4b` has no PCIe/USB/Ethernet and no Wi-Fi chip (PCIe+GENET patches are
still under review), which is why the network part runs on `virt`. What remains unproven
without hardware: the Broadcom radio itself accepting AP mode (standard brcmfmac + hostapd
nl80211 setup, used widely on Pi 4) and the hardware H.264 encoder (libx264 fallback is
automatic).

```bash
scripts/docker.sh scripts/test.sh          # all three
scripts/docker.sh scripts/test.sh e2e      # only one layer
```
Interactive VM: `DOCKER_ARGS="-p 2222:2222 -p 8080:8080" scripts/docker.sh scripts/run-qemu-virt.sh`,
then `ssh -p 2222 root@localhost`, `vlc http://localhost:8080/stream.m3u8`.

## Layout
```
buildroot/            Buildroot submodule (pinned)
br2-external/         our Buildroot tree: defconfigs, board files, rootfs overlay
docker/Dockerfile     build + QEMU + test environment
scripts/              build.sh, docker.sh, run-qemu-*.sh, test.sh, audit-image.sh
tests/                pytest end-to-end tests (run against QEMU virt)
```
