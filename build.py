"""Builds Mowser for Android in a Modal Function.

The checkout and build output live on the container's local disk under /work. At the end of
each run /work is packed into one zstd archive on the `mowser-state` Volume, and the next run
unpacks it, so builds are incremental. Finished packages go to the `mowser-out` Volume as
mowser-<target>.<apk|tar.zst|zip>; see scripts/build.sh.

Usage:
    modal run --detach build.py    # sync if needed, then build android-arm64 and android-x64
    MOWSER_TARGETS=android-arm64 modal run --detach build.py    # build only android-arm64
    modal volume get mowser-out mowser-android-arm64.apk .

The checkout is synced when there is no archive, or when CHROMIUM_VERSION differs from the
archived checkout's version.
"""

import os
import subprocess
from pathlib import Path

import modal

ROOT = Path(__file__).parent
CHROMIUM_VERSION = os.environ.get(
    "CHROMIUM_VERSION", (ROOT / "chromium-version").read_text().strip()
)
MOWSER_TARGETS = os.environ.get("MOWSER_TARGETS", "android-arm64 android-x64")

WORK = Path("/work")
STATE = Path("/state")
ARCHIVE = STATE / "work.tar.zst"
VERSION_FILE = WORK / "chromium-version"

GITILES = f"https://chromium.googlesource.com/chromium/src/+/refs/tags/{CHROMIUM_VERSION}"
SYSTEM_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

image = (
    modal.Image.from_registry("ubuntu:24.04", add_python="3.12")
    .apt_install("git", "curl", "sudo", "lsb-release", "file", "xz-utils", "zip", "unzip", "zstd")
    .run_commands(
        f"curl -fsSL '{GITILES}/build/install-build-deps.py?format=TEXT'"
        " | base64 -d > /tmp/install-build-deps.py",
        "python3 /tmp/install-build-deps.py --android --no-prompt"
        " --no-chromeos-fonts --no-arm --no-nacl --no-syms",
        "git clone --depth 1"
        " https://chromium.googlesource.com/chromium/tools/depot_tools.git /depot_tools",
        # The first gclient run bootstraps depot_tools' own Python and CIPD client.
        "cd /depot_tools && ./gclient --version",
        # Check out files with one worker per core.
        "git config --global checkout.workers 0",
    )
    .env({"PATH": f"/depot_tools:{SYSTEM_PATH}", "DEPOT_TOOLS_UPDATE": "0"})
    .add_local_dir(ROOT / "scripts", "/mowser/scripts")
    .add_local_dir(ROOT / "patches", "/mowser/patches")
    .add_local_dir(ROOT / "args", "/mowser/args")
    # build.py runs from /root in the container and reads the version next to it.
    .add_local_file(ROOT / "chromium-version", "/root/chromium-version")
)

app = modal.App("mowser")
out_volume = modal.Volume.from_name("mowser-out", create_if_missing=True, version=2)
state_volume = modal.Volume.from_name("mowser-state", create_if_missing=True, version=2)


def run(cmd: str, **env: str) -> None:
    print(f"+ {cmd}", flush=True)
    subprocess.run(["bash", "-c", cmd], check=True, env={**os.environ, **env})


@app.function(
    image=image,
    cpu=32,
    memory=64 * 1024,
    ephemeral_disk=400 * 1024,
    timeout=3 * 3600,
    volumes={"/out": out_volume, str(STATE): state_volume},
)
def build(targets: str) -> None:
    if ARCHIVE.exists():
        run(f"zstd -d -T0 --long=31 -c {ARCHIVE} | tar -x -C /")
    if not VERSION_FILE.exists() or VERSION_FILE.read_text().strip() != CHROMIUM_VERSION:
        run("bash /mowser/scripts/sync.sh", CHROMIUM_VERSION=CHROMIUM_VERSION)
        VERSION_FILE.write_text(CHROMIUM_VERSION)

    run("rm -rf /work/patches /work/args && cp -r /mowser/patches /mowser/args /work/")
    try:
        run("bash /mowser/scripts/build.sh", MOWSER_TARGETS=targets)
    finally:
        # Keep the build state even when the build fails, so fixes rebuild incrementally.
        run(f"tar -C / -cf - work | zstd -1 -T0 --long=31 -q -o {ARCHIVE}.tmp && mv {ARCHIVE}.tmp {ARCHIVE}")
        state_volume.commit()
        out_volume.commit()


@app.local_entrypoint()
def main() -> None:
    build.remote(MOWSER_TARGETS)
