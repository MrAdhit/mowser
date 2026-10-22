#!/usr/bin/env bash
# Fetches Chromium $CHROMIUM_VERSION into $MOWSER_WORK/src (default /work/src) and runs the
# gclient hooks. MOWSER_SYNC_JOBS sets the number of parallel fetches (default: CPU count);
# googlesource.com answers HTTP 429 when one address opens too many.
set -euo pipefail

work="${MOWSER_WORK:-/work}"

mkdir -p "$work"
cd "$work"
cat > .gclient <<'EOF'
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
target_os = ["android"]
EOF

if [ -d src/.git ]; then
  git -C src reset --hard HEAD
  git -C src clean -fd
fi

# A commit hash lets gclient fetch with --depth=1. A tag name makes it fetch the whole remote,
# which stalls on an existing shallow checkout.
revision=$(git -C src rev-parse --verify -q "refs/tags/${CHROMIUM_VERSION}^{commit}" 2>/dev/null \
  || echo "refs/tags/${CHROMIUM_VERSION}")

echo "=== sync start $(date -Iseconds) at ${revision}"
gclient sync --revision "src@${revision}" \
  --no-history --nohooks -D --force --jobs "${MOWSER_SYNC_JOBS:-$(nproc)}"
echo "=== hooks start $(date -Iseconds)"
gclient runhooks --jobs "$(nproc)"
echo "=== sync done $(date -Iseconds)"
du -sh "$work/src"
