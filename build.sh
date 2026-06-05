#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${THEOS:=${HOME}/theos}"
export THEOS
MODE="${1:-rootless}"; shift || true
mkdir -p packages
case "$MODE" in
  rootless) echo "[FBTweaks] rootless package"; make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless "$@" ;;
  rootful)  echo "[FBTweaks] rootful package";  make package FINALPACKAGE=1 "$@" ;;
  dylib)    echo "[FBTweaks] dylib only"; make FINALPACKAGE=1 "$@"; cp -f .theos/obj/FBTweaks.dylib packages/FBTweaks.dylib ;;
  clean)    make clean || true; rm -rf .theos ;;
  *)        make package FINALPACKAGE=1 "$MODE" "$@" ;;
esac
[ "$MODE" = clean ] || ls -la packages
