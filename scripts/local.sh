#!/usr/bin/env bash
# Builds Mowser on a Linux machine with Chromium's Android build dependencies installed.
#
# Copies patches/ and args/ to $MOWSER_WORK (default ~/chromium), syncs Chromium
# $CHROMIUM_VERSION into $MOWSER_WORK/src when there is no checkout of that version, then runs
# scripts/build.sh. Packages are written to $MOWSER_OUT (default ~/mowser-out). depot_tools must
# be on PATH. MOWSER_TARGETS (default "android-arm64"), MOWSER_TARGET_OS and MOWSER_SYNC_JOBS
# are passed through.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
export CHROMIUM_VERSION="${CHROMIUM_VERSION:-$(cat "$repo/chromium-version")}"
export MOWSER_WORK="${MOWSER_WORK:-$HOME/chromium}"
export MOWSER_OUT="${MOWSER_OUT:-$HOME/mowser-out}"
export MOWSER_TARGETS="${MOWSER_TARGETS:-android-arm64}"

mkdir -p "$MOWSER_WORK"
rm -rf "$MOWSER_WORK/patches" "$MOWSER_WORK/args"
cp -r "$repo/patches" "$repo/args" "$MOWSER_WORK/"

version_file="$MOWSER_WORK/chromium-version"
if [ "$(cat "$version_file" 2>/dev/null)" != "$CHROMIUM_VERSION" ]; then
  bash "$repo/scripts/sync.sh"
  echo "$CHROMIUM_VERSION" > "$version_file"
fi

bash "$repo/scripts/build.sh"
