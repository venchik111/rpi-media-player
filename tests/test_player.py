"""End-to-end checks on the QEMU twin. Tests run in file order on one VM."""
import re
import subprocess
import time


def media_sequence(text):
    m = re.search(r"#EXT-X-MEDIA-SEQUENCE:(\d+)", text)
    return int(m.group(1)) if m else None


def test_services_up(vm):
    rc, out, _ = vm.run("pidof sshd hostapd dnsmasq lighttpd ffmpeg | wc -w")
    assert rc == 0 and int(out.strip()) >= 5, out


def test_storage_mounted(vm):
    rc, out, _ = vm.run("mount")
    assert " on /data type ext4" in out
    if vm.rootfs == "pi":
        assert " on /boot type vfat" in out


def test_access_point_uses_config(vm, expected_ssid):
    # For the Pi rootfs the SSID was changed in BOOT:/rpi-player.conf (CRLF).
    rc, out, _ = vm.run("cat /run/hostapd.conf; ip -4 addr show wlan0")
    assert f"ssid={expected_ssid}\n" in out and "wpa=2" in out
    assert "192.168.50.1/24" in out
    rc, out, _ = vm.run("iw dev wlan0 info")
    assert "type AP" in out and f"ssid {expected_ssid}" in out


def test_ssh_host_keys_persist_on_data(vm):
    rc, out, _ = vm.run("ls /data/ssh")
    assert "ssh_host_ed25519_key" in out


def test_placeholder_before_upload(vm):
    assert vm.state().get("mode") == "placeholder"
    r = vm.wait_for(lambda: vm.get("/stream.m3u8").ok and vm.get("/stream.m3u8"))
    assert r.headers["Content-Type"].startswith("application/vnd.apple.mpegurl")
    assert "#EXT-X-ENDLIST" not in r.text  # live, like a camera


def test_sftp_upload_switches_to_video(vm, media):
    # uploaded by the 'media' user (password from rpi-player.conf), not root
    vm.upload(media["h264"], "/data/media/clip_h264.mp4")
    st = vm.wait_for(lambda: vm.state().get("mode") == "video" and vm.state(), timeout=60)
    assert st["source"] == "/data/media/clip_h264.mp4"
    rc, out, _ = vm.run("ls -l /data/media/clip_h264.mp4 | awk '{print $3}'")
    assert out.strip() == "media"


def test_playlist_is_live_and_advances(vm):
    first = vm.wait_for(lambda: media_sequence(vm.get("/stream.m3u8").text))
    time.sleep(8)
    second = media_sequence(vm.get("/stream.m3u8").text)
    assert second > first


def test_segment_is_h264(vm, tmp_path):
    text = vm.get("/stream.m3u8").text
    seg = [l for l in text.splitlines() if l.endswith(".ts")][-1]
    data = vm.get("/" + seg).content
    f = tmp_path / "seg.ts"
    f.write_bytes(data)
    codec = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                            "-show_entries", "stream=codec_name", "-of", "csv=p=0", str(f)],
                           capture_output=True, text=True, check=True).stdout.split()[0]
    assert codec == "h264"


def test_non_h264_upload_is_transcoded(vm, media):
    vm.upload(media["mpeg4"], "/data/media/clip_mpeg4.avi")
    st = vm.wait_for(lambda: vm.state().get("cached") and vm.state(), timeout=300)
    assert st["mode"] == "video" and st["source"].endswith("clip_mpeg4.avi")


def stream_codecs(vm, tmp_path):
    """Codecs in the newest live segment, e.g. {"h264", "aac"}."""
    text = vm.get("/stream.m3u8").text
    seg = [l for l in text.splitlines() if l.endswith(".ts")][-1]
    f = tmp_path / "live.ts"
    f.write_bytes(vm.get("/" + seg).content)
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name",
                          "-of", "csv=p=0", str(f)], capture_output=True, text=True).stdout
    return set(out.replace(",", " ").split())


def test_aac_sound_is_in_the_stream(vm, media, tmp_path):
    vm.upload(media["aac"], "/data/media/clip_aac.mp4")
    vm.wait_for(lambda: vm.state().get("source") == "/data/media/clip_aac.mp4", timeout=60)
    assert vm.wait_for(lambda: stream_codecs(vm, tmp_path) == {"h264", "aac"}, timeout=60)


def test_other_sound_formats_become_aac(vm, media, tmp_path):
    vm.upload(media["ac3"], "/data/media/clip_ac3.mkv")
    st = vm.wait_for(lambda: vm.state().get("cached") and vm.state().get("source", "").endswith("clip_ac3.mkv")
                     and vm.state(), timeout=120)
    assert st["mode"] == "video"
    assert vm.wait_for(lambda: stream_codecs(vm, tmp_path) == {"h264", "aac"}, timeout=60)


def test_failed_uploads_keep_the_stream_running(vm, media):
    vm.upload(media["aac"], "/data/media/good.mp4")
    vm.wait_for(lambda: vm.state().get("source") == "/data/media/good.mp4", timeout=60)
    _, ffmpeg_before, _ = vm.run("pidof ffmpeg")
    first = media_sequence(vm.get("/stream.m3u8").text)

    for name in ("broken_no_index", "broken_with_index"):
        vm.upload(media[name], f"/data/media/{name}.mp4")
        time.sleep(1.5)  # newer mtime than the previous file
    time.sleep(6)

    st = vm.state()
    assert st["mode"] == "video" and st["source"] == "/data/media/good.mp4", st
    _, ffmpeg_after, _ = vm.run("pidof ffmpeg")
    assert ffmpeg_after == ffmpeg_before  # same video, stream not restarted
    assert media_sequence(vm.get("/stream.m3u8").text) > first


def test_nothing_is_deleted_automatically(vm):
    _, out, _ = vm.run("ls /data/media")
    for name in ("clip_h264.mp4", "clip_aac.mp4", "good.mp4", "broken_no_index.mp4", "broken_with_index.mp4"):
        assert name in out, out


def test_index_page(vm):
    assert "stream.m3u8" in vm.get("/").text


def test_wifi_client_gets_stream(vm):
    rc, out, err = vm.run("/usr/libexec/rpi-player/selftest-wifi", timeout=120)
    assert rc == 0, out + err
