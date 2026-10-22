#!/usr/bin/env bash
# Installs the APK at $1 on the emulator, then stops the local adb server so the emulator is
# free for the client adb connection. The install is retried because the package manager
# can drop the connection while the emulator is busy.
set -euo pipefail

adb="$ANDROID_HOME/platform-tools/adb"
remote="/data/local/tmp/$(basename "$1")"
trap '"$adb" kill-server' EXIT
# A newly started adb server reports the emulator as offline for a few seconds.
timeout 120 "$adb" wait-for-device
"$adb" push "$1" "$remote"
for attempt in 1 2 3; do
  if timeout 900 "$adb" shell pm install -r -g "$remote" 2>&1 | tee /tmp/pm-install.log \
      && grep -q '^Success' /tmp/pm-install.log; then
    "$adb" shell rm "$remote"
    exit 0
  fi
  echo "install attempt ${attempt} failed; retrying in 30s"
  sleep 30
done
exit 1
