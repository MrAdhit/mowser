#!/usr/bin/env bash
# Fetches Chromium $CHROMIUM_VERSION into $MOWSER_WORK/src (default /work/src) and runs the
# gclient hooks. MOWSER_TARGET_OS lists the operating systems whose dependencies are fetched
# besides the host's (default "android"). MOWSER_SYNC_JOBS sets the number of parallel fetches
# (default: CPU count); googlesource.com answers HTTP 429 when one address opens too many.
#
# When MOWSER_REAPI_ADDRESS is set, Siso is configured for remote execution on that REAPI
# address (e.g. remote.buildbuddy.io:443) with siso/backend.star, authenticating with
# siso/credential-helper.sh, which needs MOWSER_BUILDBUDDY_API_KEY when Siso runs.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="${MOWSER_WORK:-/work}"
target_os=""
for os in ${MOWSER_TARGET_OS-android}; do
  target_os+="\"${os}\", "
done

custom_vars=""
if [ -n "${MOWSER_REAPI_ADDRESS:-}" ]; then
  custom_vars="
    \"reapi_address\": \"${MOWSER_REAPI_ADDRESS}\",
    \"reapi_instance\": \"default\",
    \"reapi_backend_config_path\": \"${repo}/siso/backend.star\",
    \"reapi_credential_helper\": \"${repo}/siso/credential-helper.sh\",
  "
fi

mkdir -p "$work"
cd "$work"
cat > .gclient <<EOF
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {${custom_vars}},
  },
]
target_os = [${target_os}]
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
