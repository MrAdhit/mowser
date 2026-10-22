#!/usr/bin/env bash
# Runs the emulator in the foreground and forwards 0.0.0.0:$1 to its adb port.
set -euo pipefail

port="$1"
"$ANDROID_HOME/platform-tools/adb" start-server
socat "TCP-LISTEN:${port},fork,reuseaddr" TCP:127.0.0.1:5555 &
exec "$ANDROID_HOME/emulator/emulator" -avd mowser \
  -no-window -no-audio -no-boot-anim -no-snapshot \
  -accel off -cores 8 -memory 4096 -gpu swiftshader_indirect \
  > /tmp/emulator.log 2>&1
