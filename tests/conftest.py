"""Boots the QEMU 'virt' twin once per session and gives tests SSH/HTTP access."""
import os
import socket
import subprocess
import time
from pathlib import Path

import paramiko
import pytest
import requests

ROOT = Path(__file__).resolve().parent.parent
SSH_PORT = int(os.environ.get("SSH_PORT", "2222"))
HTTP_PORT = int(os.environ.get("HTTP_PORT", "8080"))
RUN_DIR = Path(os.environ.get("RUN_DIR", "/work/qemu-run"))
SERIAL_LOG = RUN_DIR / "serial.log"
BOOT_TIMEOUT = int(os.environ.get("BOOT_TIMEOUT", "300"))  # TCG emulation is slow


def _ssh_client():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect("127.0.0.1", port=SSH_PORT, username="root", password="player",
              timeout=10, banner_timeout=30, auth_timeout=30,
              allow_agent=False, look_for_keys=False)
    return c


@pytest.fixture(scope="session")
def vm():
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, FRESH="1", SERIAL=f"file:{SERIAL_LOG}",
               SSH_PORT=str(SSH_PORT), HTTP_PORT=str(HTTP_PORT))
    proc = subprocess.Popen([str(ROOT / "scripts/run-qemu-virt.sh")], env=env,
                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    deadline = time.time() + BOOT_TIMEOUT
    client = None
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"qemu exited with {proc.returncode}")
        try:
            client = _ssh_client()
            break
        except (paramiko.SSHException, socket.error, EOFError):
            time.sleep(3)
    if client is None:
        proc.kill()
        pytest.fail("VM did not come up; see " + str(SERIAL_LOG))
    yield VM(client)
    client.close()
    proc.terminate()
    try:
        proc.wait(10)
    except subprocess.TimeoutExpired:
        proc.kill()


class VM:
    def __init__(self, client):
        self.ssh = client
        self.http = f"http://127.0.0.1:{HTTP_PORT}"

    def run(self, cmd, timeout=120):
        _, out, err = self.ssh.exec_command(cmd, timeout=timeout)
        rc = out.channel.recv_exit_status()
        return rc, out.read().decode(), err.read().decode()

    def state(self):
        _, out, _ = self.run("player-ctl status")
        return dict(l.split("=", 1) for l in out.split() if "=" in l)

    def upload(self, local, remote):
        sftp = self.ssh.open_sftp()
        try:
            sftp.put(str(local), remote)
        finally:
            sftp.close()

    def get(self, path, **kw):
        return requests.get(self.http + path, timeout=10, **kw)

    def wait_for(self, predicate, timeout=180, interval=2):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            try:
                last = predicate()
                if last:
                    return last
            except requests.RequestException:
                pass
            time.sleep(interval)
        raise AssertionError(f"condition not met in {timeout}s (last={last!r})")


@pytest.fixture(scope="session")
def media(tmp_path_factory):
    """Test clips generated on the host with ffmpeg."""
    d = tmp_path_factory.mktemp("media")
    h264 = d / "clip_h264.mp4"
    mpeg4 = d / "clip_mpeg4.avi"
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=25",
                    "-t", "6", "-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p", str(h264)], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25",
                    "-t", "4", "-c:v", "mpeg4", str(mpeg4)], check=True)
    return {"h264": h264, "mpeg4": mpeg4}
