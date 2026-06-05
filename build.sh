#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${THEOS:=${HOME}/theos}"
export THEOS
MODE="${1:-rootless}"
mkdir -p packages
case "$MODE" in
  rootless) shift || true; echo "[FBTweaks] Building rootless package SDK26.2"; make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless "$@" ;;
  rootful)  shift || true; echo "[FBTweaks] Building rootful package SDK26.2";  make package FINALPACKAGE=1 "$@" ;;
  dylib)    shift || true; echo "[FBTweaks] Building dylib only"; make FINALPACKAGE=1 "$@"; cp -f .theos/obj/FBTweaks.dylib packages/FBTweaks.dylib ;;
  clean)    make clean 2>/dev/null || true; rm -rf .theos ;;
  *)        echo "[FBTweaks] Building package target: $MODE"; make package FINALPACKAGE=1 "$MODE" "$@" ;;
esac
if [ "$MODE" != "clean" ]; then echo "[FBTweaks] Done"; ls -la packages || true; fi
