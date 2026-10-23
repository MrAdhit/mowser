#!/usr/bin/env bash
# Bazel credential helper (https://github.com/EngFlow/credential-helper-spec) that Siso runs for
# BuildBuddy. Answers every request with the API key in $MOWSER_BUILDBUDDY_API_KEY.
set -euo pipefail

cat > /dev/null
printf '{"headers":{"x-buildbuddy-api-key":["%s"]}}\n' "${MOWSER_BUILDBUDDY_API_KEY:?}"
