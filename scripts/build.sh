#!/usr/bin/env bash
# Applies $MOWSER_WORK/patches/*.patch (default /work) to a clean tree, writes the bundled
# uBlock Origin (scripts/ubo.sh), builds chrome_public_apk for each CPU in $MOWSER_CPUS (default
# "arm64 x64": arm64 for phones, x64 for the emulator), and copies the APKs to $MOWSER_OUT
# (default /out, the mowser-out Volume) as ChromePublic-<cpu>.apk, plus a zstd-compressed
# ChromePublic-<cpu>.apk.zst for downloading.
set -euo pipefail

work="${MOWSER_WORK:-/work}"
out_dir="${MOWSER_OUT:-/out}"
mkdir -p "$out_dir"
cd "$work/src"
# Reset only touches files that differ, so only patched files are rebuilt.
git reset --hard HEAD
git clean -fd
for patch in "$work"/patches/*.patch; do
  [ -e "$patch" ] || continue
  git apply --verbose "$patch"
done
bash "$(dirname "$0")/ubo.sh" chrome/android/mowser/ublock_origin.zip

for cpu in ${MOWSER_CPUS:-arm64 x64}; do
  out="out/mowser-${cpu}"
  mkdir -p "$out"
  sed "s/^target_cpu = .*/target_cpu = \"${cpu}\"/" "$work/args.gn" > /tmp/args.gn
  # Rewriting an unchanged args.gn makes ninja rerun gn gen.
  cmp -s /tmp/args.gn "$out/args.gn" || cp /tmp/args.gn "$out/args.gn"

  echo "=== build ${cpu} start $(date -Iseconds)"
  gn gen "$out"
  autoninja -C "$out" chrome_public_apk
  echo "=== build ${cpu} done $(date -Iseconds)"

  cp "$out/apks/ChromePublic.apk" "$out_dir/ChromePublic-${cpu}.apk"
  zstd -q -f -T0 -19 --long=27 "$out_dir/ChromePublic-${cpu}.apk" -o "$out_dir/ChromePublic-${cpu}.apk.zst"
done

sync "$out_dir"
ls -l "$out_dir"
