#!/usr/bin/env bash
# Applies $MOWSER_WORK/patches/*.patch (default /work) to a clean tree, writes the bundled
# uBlock Origin (scripts/ubo.sh), and builds each target in $MOWSER_TARGETS (default
# "android-arm64"). Needs GNU coreutils and findutils on PATH.
#
# A target is <os>-<cpu>: os is android, linux, win or mac, and cpu is a GN target_cpu. A
# target builds in out/<target> with $MOWSER_WORK/args/common.gn, $MOWSER_WORK/args/<os>.gn and
# its target_cpu, and its package is written to $MOWSER_OUT (default /out):
#   android  mowser-<target>.apk
#   linux    mowser-<target>.tar.zst, the browser's runtime files
#   win      mowser-<target>.zip, the browser's runtime files
#   mac      mowser-<target>.zip, holding Chromium.app
#
# Desktop targets build with the Google API key and OAuth client in MOWSER_GOOGLE_API_KEY,
# MOWSER_GOOGLE_CLIENT_ID and MOWSER_GOOGLE_CLIENT_SECRET when they are set.
#
# When MOWSER_DEADLINE (Unix time) is set, the build stops at that time and the script exits
# with code 124, leaving out/<target> to be resumed by a later run. In that mode source file
# times are set to a fixed past date after patching, so that an out/<target> restored from an
# earlier run on another machine stays up to date.
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
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
bash "$scripts/ubo.sh" mowser/ublock_origin.zip

if [ -n "${MOWSER_DEADLINE:-}" ]; then
  echo "=== normalizing source times $(date -Iseconds)"
  find . -path ./out -prune -o -newermt "2001-01-02" -print0 \
    | xargs -0 -r touch -h -d "2001-01-01"
fi

for target in ${MOWSER_TARGETS:-android-arm64}; do
  os="${target%%-*}"
  cpu="${target#*-}"
  out="out/${target}"
  mkdir -p "$out"

  {
    cat "$work/args/common.gn" "$work/args/${os}.gn"
    echo "target_cpu = \"${cpu}\""
    if [ "$os" != android ] && [ -n "${MOWSER_GOOGLE_API_KEY:-}" ]; then
      echo "google_api_key = \"${MOWSER_GOOGLE_API_KEY}\""
      echo "google_default_client_id = \"${MOWSER_GOOGLE_CLIENT_ID}\""
      echo "google_default_client_secret = \"${MOWSER_GOOGLE_CLIENT_SECRET}\""
    fi
  } > "$work/args.gn.new"
  # Rewriting an unchanged args.gn makes ninja rerun gn gen.
  cmp -s "$work/args.gn.new" "$out/args.gn" || cp "$work/args.gn.new" "$out/args.gn"
  rm -f "$work/args.gn.new"

  case "$os" in
    android) ninja_target=chrome_public_apk ;;
    *) ninja_target=chrome ;;
  esac

  echo "=== build ${target} start $(date -Iseconds)"
  [ -e "$out/build.ninja" ] || gn gen "$out"
  if [ -n "${MOWSER_DEADLINE:-}" ]; then
    remaining=$((MOWSER_DEADLINE - $(date +%s)))
    if [ "$remaining" -le 0 ]; then
      echo "=== build ${target} out of time"
      exit 124
    fi
    status=0
    timeout --signal=INT --kill-after=5m "$remaining" autoninja -C "$out" "$ninja_target" \
      || status=$?
    if [ "$status" -ne 0 ]; then
      # autoninja exits with 130 when the INT from timeout stops it.
      if [ "$status" -eq 124 ] || [ "$status" -eq 130 ]; then
        echo "=== build ${target} stopped at the deadline $(date -Iseconds)"
        exit 124
      fi
      exit "$status"
    fi
  else
    autoninja -C "$out" "$ninja_target"
  fi
  echo "=== build ${target} done $(date -Iseconds)"

  case "$os" in
    android)
      cp "$out/apks/ChromePublic.apk" "$out_dir/mowser-${target}.apk"
      ;;
    linux)
      # The runtime deps that live in the build directory are the browser's files.
      gn desc "$out" //chrome:chrome runtime_deps | grep -v '^\.\./' \
        | tar -C "$out" --zstd -cf "$out_dir/mowser-${target}.tar.zst" -T -
      ;;
    win)
      rm -f "$out_dir/mowser-${target}.zip"
      gn desc "$out" //chrome:chrome runtime_deps | grep -v '^\.\./' \
        | (cd "$out" && zip -q -r -@ "$out_dir/mowser-${target}.zip")
      ;;
    mac)
      rm -f "$out_dir/mowser-${target}.zip"
      ditto -c -k --keepParent "$out/Chromium.app" "$out_dir/mowser-${target}.zip"
      ;;
  esac
done

ls -l "$out_dir"
