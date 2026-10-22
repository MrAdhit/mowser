#!/usr/bin/env bash
# Builds Mowser on a Linux machine with Chromium's Android build dependencies installed.
#
# Copies patches/ and args.gn to $MOWSER_WORK (default ~/chromium), syncs Chromium
# $CHROMIUM_VERSION into $MOWSER_WORK/src when there is no checkout of that version, then runs
# scripts/build.sh. APKs are written to $MOWSER_OUT (default ~/mowser-out). depot_tools must be
# on PATH. MOWSER_CPUS (default "arm64") and MOWSER_SYNC_JOBS are passed through.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
export CHROMIUM_VERSION="${CHROMIUM_VERSION:-156.0.8078.47}"
export MOWSER_WORK="${MOWSER_WORK:-$HOME/chromium}"
export MOWSER_OUT="${MOWSER_OUT:-$HOME/mowser-out}"
export MOWSER_CPUS="${MOWSER_CPUS:-arm64}"

mkdir -p "$MOWSER_WORK"
rm -rf "$MOWSER_WORK/patches"
cp -r "$repo/patches" "$MOWSER_WORK/patches"
cp "$repo/args.gn" "$MOWSER_WORK/args.gn"

version_file="$MOWSER_WORK/chromium-version"
if [ "$(cat "$version_file" 2>/dev/null)" != "$CHROMIUM_VERSION" ]; then
  bash "$repo/scripts/sync.sh"
  echo "$CHROMIUM_VERSION" > "$version_file"
fi

bash "$repo/scripts/build.sh"
