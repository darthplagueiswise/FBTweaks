#!/usr/bin/env bash
# build.sh — build FBTweaks package
set -euo pipefail

cd "$(dirname "$0")"

echo "[FBTweaks] Building..."
make package FINALPACKAGE=1 "$@"
echo "[FBTweaks] Done."
