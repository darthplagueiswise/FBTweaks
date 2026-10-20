#!/bin/bash
set -euo pipefail
DEB="${1:?usage: verify_macho_installation.sh built.deb}"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
dpkg-deb -x "$DEB" "$ROOT"
DYLIB="$(find "$ROOT" -type f -name FBTweak.dylib -print -quit)"
test -n "$DYLIB" || { echo "FBTweak.dylib missing from package"; exit 1; }
echo "Architectures:"
lipo -archs "$DYLIB" | tee "$ROOT/arches"
grep -qw arm64 "$ROOT/arches"
echo "LC_ID_DYLIB:"
otool -D "$DYLIB"
echo "LC_LOAD_DYLIB dependencies:"
otool -L "$DYLIB"
if otool -L "$DYLIB" | grep -q FridaGadget; then echo "Unexpected Frida dependency"; exit 1; fi
echo "Rootless package Mach-O checked; Feather IPA must separately validate actual LC_LOAD_DYLIB path, nested signatures and Substrate."
