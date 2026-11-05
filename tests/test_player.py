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


def test_access_point_uses_config(vm):
    rc, out, _ = vm.run("cat /run/hostapd.conf; ip -4 addr show wlan0")
    assert "ssid=rpi-cam" in out and "wpa=2" in out
    assert "192.168.50.1/24" in out


def test_placeholder_before_upload(vm):
    assert vm.state().get("mode") == "placeholder"
    r = vm.wait_for(lambda: vm.get("/stream.m3u8").ok and vm.get("/stream.m3u8"))
    assert r.headers["Content-Type"].startswith("application/vnd.apple.mpegurl")
    assert "#EXT-X-ENDLIST" not in r.text  # live, like a camera


def test_sftp_upload_switches_to_video(vm, media):
    vm.upload(media["h264"], "/data/media/clip_h264.mp4")
    st = vm.wait_for(lambda: vm.state().get("mode") == "video" and vm.state(), timeout=60)
    assert st["source"] == "/data/media/clip_h264.mp4"


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
                           capture_output=True, text=True, check=True).stdout.strip()
    assert codec == "h264"


def test_non_h264_upload_is_transcoded(vm, media):
    vm.upload(media["mpeg4"], "/data/media/clip_mpeg4.avi")
    st = vm.wait_for(lambda: vm.state().get("cached") and vm.state(), timeout=300)
    assert st["mode"] == "video" and st["source"].endswith("clip_mpeg4.avi")


def test_index_page(vm):
    assert "stream.m3u8" in vm.get("/").text


def test_wifi_client_gets_stream(vm):
    rc, out, err = vm.run("/usr/libexec/rpi-player/selftest-wifi", timeout=120)
    assert rc == 0, out + err
