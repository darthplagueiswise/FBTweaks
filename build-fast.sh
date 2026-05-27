#!/usr/bin/env bash
# build-fast.sh — quick local build without final package compression
set -euo pipefail
cd "$(dirname "$0")"
echo "[FBTweaks] Fast build..."
make package "$@"
