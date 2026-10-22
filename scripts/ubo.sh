#!/usr/bin/env bash
# Writes uBlock Origin $UBO_VERSION, as bundled in the APK, to the path in $1.
#
# Downloads the Chromium build from the gorhill/uBlock GitHub release, checks its SHA-256,
# adds Mowser's public key to manifest.json, which gives the extension the ID
# cbnhekcmihffpmkhiolglckkhmplkhpe, and zips the extension files at the archive root.
set -euo pipefail

UBO_VERSION="1.75.0"
UBO_SHA256="393cf95709d1074d4022970e9014e434395c53a822387f1e25f43be97cf4b582"
UBO_KEY="MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1xp/fhy8eAlKuhBQ5iDK1LwPvv7GryfV0EUXZbHb24UtXTYellF4cTEW4TewXcjHF4hbGiQZ0kCd7QZLqrVdQJm/mrSWQR5BtySoxF2rsVVdds2DKBUHJCyyu1/JoD4ZXkbHw7uTdNuA7vhMGkrpm2FkaZpZ/LgaUQvZncrVhGTvdPbCT09kvuz/2kbzZqwHGv2aFXeALm3/ZW0SkWE79+qRGub+6AX0EWKMOlkXnEsG5yNjzlm73285jN0n24LuekQks4fsdVPfAOyiXJXv+xyZNwVVXD+wCNAyV4+oEMx0CvHGJcixMjCz+pU9UXJ7Uw6+OWZ7+Eh7jDHFfvcpqwIDAQAB"

out="$(realpath -m "$1")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/ubo.zip" \
  "https://github.com/gorhill/uBlock/releases/download/${UBO_VERSION}/uBlock0_${UBO_VERSION}.chromium.zip"
echo "${UBO_SHA256}  $tmp/ubo.zip" | sha256sum -c --quiet

unzip -q "$tmp/ubo.zip" -d "$tmp"
python3 - "$tmp/uBlock0.chromium/manifest.json" "$UBO_KEY" <<'EOF'
import json
import sys

path, key = sys.argv[1:]
with open(path) as f:
    manifest = json.load(f)
manifest["key"] = key
with open(path, "w") as f:
    json.dump(manifest, f, indent=2)
EOF

mkdir -p "$(dirname "$out")"
rm -f "$out"
(cd "$tmp/uBlock0.chromium" && zip -q -r -X "$out" .)
echo "uBlock Origin ${UBO_VERSION} written to $out"
