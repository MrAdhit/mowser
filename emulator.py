"""Runs an Android emulator in a Modal VM sandbox.

Modal sandboxes have no KVM, so the emulator runs an Android 11 (API 30) x86_64 image with
software emulation (`-accel off`). It boots in about four minutes on 16 cores.

adb is exposed through a Modal TCP tunnel. The emulator only accepts adb connections from the
key in ~/.android/adbkey.pub, which `up` installs into it. MicroG-RE is installed on boot.
The emulator serves one adb connection at a time, so `install` disconnects the local adb from
the tunnel while it installs from inside the sandbox, then reconnects it.

Usage:
    python emulator.py up                # boot the emulator and print the adb address
    python emulator.py install <apk>     # install an APK: a local path, or a file on mowser-out
    python emulator.py down              # terminate the sandbox
    adb connect <host>:<port> && scrcpy -s <host>:<port>

The running sandbox's ID is kept in `.emulator-id`. The sandbox stops after
MOWSER_EMULATOR_HOURS hours (default 2), or 10 minutes after the emulator exits.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import modal

ROOT = Path(__file__).parent
SANDBOX_ID_FILE = ROOT / ".emulator-id"
ADB_PORT = 7555
SYSTEM_IMAGE = "system-images;android-30;google_apis;x86_64"
SANDBOX_TIMEOUT = int(float(os.environ.get("MOWSER_EMULATOR_HOURS", "2")) * 3600)
SANDBOX_IDLE_TIMEOUT = 10 * 60
SETUP_TIMEOUT = 25 * 60

SDK = "/sdk"
SDKMANAGER = f"{SDK}/cmdline-tools/latest/bin/sdkmanager"

image = (
    modal.Image.from_registry("ubuntu:24.04", add_python="3.12")
    .apt_install(
        "curl", "unzip", "socat", "openjdk-17-jre-headless", "libpulse0", "libgl1", "libnss3",
        "libxcomposite1", "libxcursor1", "libxi6", "libxtst6", "libasound2t64", "libxkbfile1",
    )
    .env({"ANDROID_HOME": SDK, "ANDROID_SDK_ROOT": SDK})
    .run_commands(
        f"mkdir -p {SDK}/cmdline-tools && cd /tmp"
        " && curl -fsSL https://dl.google.com/android/repository/repository2-3.xml"
        " | grep -oE 'commandlinetools-linux-[0-9]+_latest\\.zip' | sort -u | tail -1"
        " | xargs -I{} curl -fsSL -o clt.zip https://dl.google.com/android/repository/{}"
        f" && unzip -q clt.zip && mv cmdline-tools {SDK}/cmdline-tools/latest && rm clt.zip",
        f"yes | {SDKMANAGER} --licenses > /dev/null",
        f"{SDKMANAGER} --install emulator platform-tools '{SYSTEM_IMAGE}' > /dev/null",
        f"echo no | {SDK}/cmdline-tools/latest/bin/avdmanager create avd -n mowser -k '{SYSTEM_IMAGE}'",
        "printf 'hw.lcd.width=540\\nhw.lcd.height=1080\\nhw.lcd.density=240\\nhw.keyboard=yes\\n'"
        " >> /root/.android/avd/mowser.avd/config.ini",
    )
    .add_local_dir(ROOT / "scripts" / "emulator", "/emulator")
)

app = modal.App.lookup("mowser-emulator", create_if_missing=True)
out_volume = modal.Volume.from_name("mowser-out", create_if_missing=True, version=2)


def current_sandbox() -> modal.Sandbox | None:
    if not SANDBOX_ID_FILE.exists():
        return None
    sb = modal.Sandbox.from_id(SANDBOX_ID_FILE.read_text().strip())
    if sb.poll() is not None:
        SANDBOX_ID_FILE.unlink()
        return None
    return sb


def run(sb: modal.Sandbox, cmd: str, timeout: int) -> int:
    p = sb.exec("bash", "-c", cmd, timeout=timeout)
    for line in p.stdout:
        print(line, end="", flush=True)
    p.wait()
    print(p.stderr.read(), end="", file=sys.stderr, flush=True)
    return p.returncode


def adb_address(sb: modal.Sandbox) -> str:
    host, port = sb.tunnels()[ADB_PORT].tcp_socket
    return f"{host}:{port}"


def up() -> int:
    if current_sandbox() is not None:
        print("emulator already running at", adb_address(current_sandbox()))
        return 0
    adb_key = Path.home() / ".android" / "adbkey.pub"
    if not adb_key.exists():
        print(f"{adb_key} not found; run `adb start-server` once to create it", file=sys.stderr)
        return 1
    sb = modal.Sandbox.create(
        app=app,
        image=image,
        runtime="vm",
        cpu=16,
        memory=16 * 1024,
        timeout=SANDBOX_TIMEOUT,
        idle_timeout=SANDBOX_IDLE_TIMEOUT,
        unencrypted_ports=[ADB_PORT],
        volumes={"/out": out_volume},
    )
    SANDBOX_ID_FILE.write_text(sb.object_id)
    rc = 1
    try:
        sb.filesystem.write_text(adb_key.read_text(), "/emulator/client_adbkey.pub")
        # Keeps running for the life of the emulator.
        sb.exec("bash", "/emulator/run.sh", str(ADB_PORT), timeout=SANDBOX_TIMEOUT)
        rc = run(sb, "bash /emulator/setup.sh", SETUP_TIMEOUT)
    finally:
        # A failed setup would otherwise leave the emulator running until SANDBOX_TIMEOUT.
        if rc != 0:
            sb.terminate()
            SANDBOX_ID_FILE.unlink()
    if rc != 0:
        return rc
    address = adb_address(sb)
    print(f"\nadb connect {address} && scrcpy -s {address}")
    return 0


def install(apk: str) -> int:
    sb = current_sandbox()
    if sb is None:
        print("no running emulator", file=sys.stderr)
        return 1
    if Path(apk).exists():
        remote = f"/tmp/{Path(apk).name}"
        sb.filesystem.copy_from_local(apk, remote)
    else:
        sb.reload_volumes()
        remote = f"/out/{apk}"
    local_adb = shutil.which("adb")
    address = adb_address(sb)
    if local_adb:
        subprocess.run([local_adb, "disconnect", address], capture_output=True)
    try:
        return run(sb, f"bash /emulator/install.sh '{remote}'", 20 * 60)
    finally:
        if local_adb:
            subprocess.run([local_adb, "connect", address])


def main() -> int:
    cmd, *args = sys.argv[1:] or ["up"]
    if cmd == "up":
        return up()
    if cmd == "install":
        return install(args[0])
    if cmd == "down":
        sb = current_sandbox()
        if sb is not None:
            sb.terminate()
            SANDBOX_ID_FILE.unlink()
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
