#!/usr/bin/env bash
#
# build.sh — FBTweak
# Build limpo rootless (.deb).
# Uso:
#   ./build.sh rootless        # build rootless .deb (padrao / CI)
#   ./build.sh rootless --fast # sem clean total
#   ./build.sh clean           # limpa artefatos
#
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MODE="${1:-rootless}"
FAST=0
[ "${2:-}" = "--fast" ] && FAST=1

# --- THEOS ---
if [ -z "${THEOS:-}" ]; then
  if [ -d "$HOME/theos" ]; then export THEOS="$HOME/theos"; fi
fi
if [ -z "${THEOS:-}" ] || [ ! -d "$THEOS" ]; then
  echo "ERRO: \$THEOS nao definido ou inexistente."
  exit 1
fi
echo "[FBTweak] THEOS=$THEOS"

case "$MODE" in
  clean)
    echo "[FBTweak] make clean"
    make clean || true
    rm -rf packages .theos obj
    echo "[FBTweak] limpo."
    exit 0
    ;;

  rootless|*)
    export THEOS_PACKAGE_SCHEME=rootless

    if [ "$FAST" -eq 0 ]; then
      echo "[FBTweak] make clean"
      make clean || true
    fi

    echo "[FBTweak] make FINALPACKAGE=1 package (rootless, SDK 26.2)"
    make FINALPACKAGE=1 package \
      THEOS_PACKAGE_SCHEME=rootless \
      THEOS_PLATFORM_DEB_COMPRESSION_TYPE=lzma \
      THEOS_PLATFORM_DEB_COMPRESSION_LEVEL=9

    DEB="$(ls -t packages/*.deb 2>/dev/null | head -n1 || true)"
    if [ -z "$DEB" ]; then
      echo "ERRO: nenhum .deb gerado em packages/"
      exit 1
    fi
    echo "[FBTweak] OK -> $DEB"
    ;;
esac
