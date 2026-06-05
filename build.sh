#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# FBTweaks Build Script
# RyukGram-style Theos build wrapper for SDK26.
# ============================================================

GREEN='\033[1m\033[32m'
YELLOW='\033[0;33m'
RED='\033[1m\033[0;31m'
RESET='\033[0m'

APP_NAME="FBTweaks"
PACKAGES_DIR="packages"
TWEAK_DYLIB=".theos/obj/${APP_NAME}.dylib"

log() { printf "%b\n" "${GREEN}$*${RESET}"; }
warn() { printf "%b\n" "${YELLOW}$*${RESET}"; }
die() { printf "%b\n" "${RED}$*${RESET}" >&2; exit 1; }

ensure_theos() {
	if [ -n "${THEOS:-}" ]; then return; fi
	if [ -d "$HOME/theos" ]; then
		export THEOS="$HOME/theos"
	else
		die "THEOS not set and ~/theos not found. Set THEOS or install Theos to ~/theos"
	fi
}

ensure_packages_dir() { mkdir -p "$PACKAGES_DIR"; }

clean_build() {
	make clean 2>/dev/null || true
	rm -rf .theos
}

make_package() {
	if [ "$#" -gt 0 ]; then
		make package FINALPACKAGE=1 "$@"
	else
		make package FINALPACKAGE=1
	fi
}

MODE="${1:-rootless}"
case "$MODE" in
	rootless)
		shift || true
		ensure_theos
		ensure_packages_dir
		log "[FBTweaks] Building rootless package with SDK26"
		make_package THEOS_PACKAGE_SCHEME=rootless "$@"
		;;
	rootful)
		shift || true
		ensure_theos
		ensure_packages_dir
		log "[FBTweaks] Building rootful package with SDK26"
		make_package "$@"
		;;
	dylib)
		shift || true
		ensure_theos
		clean_build
		ensure_packages_dir
		log "[FBTweaks] Building dylib only"
		make_package "$@"
		[ -f "$TWEAK_DYLIB" ] || die "Missing dylib: $TWEAK_DYLIB"
		cp -f "$TWEAK_DYLIB" "$PACKAGES_DIR/${APP_NAME}.dylib"
		;;
	clean)
		clean_build
		;;
	*)
		ensure_theos
		ensure_packages_dir
		log "[FBTweaks] Building default target: $MODE"
		make_package "$MODE" "$@"
		;;
esac

if [ "$MODE" != "clean" ]; then
	log "[FBTweaks] Done"
	ls -la "$PACKAGES_DIR" 2>/dev/null || true
fi
