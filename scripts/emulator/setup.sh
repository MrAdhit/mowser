#!/usr/bin/env bash
# Waits for the emulator to boot, authorizes /emulator/client_adbkey.pub for adb, and installs
# the latest MicroG-RE release.
set -euo pipefail

adb="$ANDROID_HOME/platform-tools/adb"
start=$(date +%s)
echo "waiting for boot"
until [ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  if ! pgrep -f "emulator.*-avd mowser" > /dev/null; then
    echo "emulator exited"; tail -20 /tmp/emulator.log; exit 1
  fi
  sleep 10
done
echo "booted in $(( $(date +%s) - start ))s"

"$adb" root > /dev/null
"$adb" wait-for-device
"$adb" shell 'cat >> /data/misc/adb/adb_keys' < /emulator/client_adbkey.pub
echo "authorized client adb key"

# Compiling apps at install time is very slow under software emulation; "extract" skips it.
"$adb" shell setprop pm.dexopt.install extract
"$adb" shell setprop pm.dexopt.bg-dexopt extract

url=$(curl -fsSL https://api.github.com/repos/ReVanced/GmsCore/releases/latest \
  | grep -oE '"browser_download_url": *"[^"]+\.apk"' | grep -v -i hw | head -1 | cut -d'"' -f4)
echo "installing $url"
curl -fsSL -o /tmp/microg.apk "$url"
if ! bash /emulator/install.sh /tmp/microg.apk; then
  "$ANDROID_HOME/platform-tools/adb" logcat -d -b system,crash,main 2>/dev/null \
    | grep -iE "watchdog|FATAL EXCEPTION|system_server|died|Blocked in" | tail -25
  exit 1
fi

