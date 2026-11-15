#!/bin/bash
set -euo pipefail
DEB="${1:?usage: verify_macho_installation.sh built.deb}"
test "$(dpkg-deb -f "$DEB" Package)" = "com.darthplagueiswise.fbtweak"
PACKAGE_ARCH="$(dpkg-deb -f "$DEB" Architecture)"
test "$PACKAGE_ARCH" = "iphoneos-arm64" || {
  echo "Unexpected Debian architecture: $PACKAGE_ARCH" >&2
  exit 1
}
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
dpkg-deb -x "$DEB" "$ROOT"
DYLIB="$ROOT/var/jb/Library/MobileSubstrate/DynamicLibraries/FBTweak.dylib"
test -f "$DYLIB" || { echo "Rootless FBTweak.dylib missing from package"; exit 1; }
test -f "$ROOT/var/jb/Library/MobileSubstrate/DynamicLibraries/FBTweak.plist"
test ! -e "$ROOT/Library/MobileSubstrate/DynamicLibraries/FBTweak.dylib"
BUNDLE="$ROOT/var/jb/Library/Application Support/FBTweak.bundle"
test -s "$BUNDLE/FBTFlags.json"
test -s "$BUNDLE/FBTHeadlineFlags.json"
test -d "$BUNDLE/QueryConfigs"
gzip -t "$BUNDLE/FBTLocalConfigNames.json.gz"
BUILD_INFO="$BUNDLE/FBTBuildInfo.json"
python3 - "$BUILD_INFO" "${FBT_EXPECTED_COMMIT:-}" <<'PYINFO'
import json, re, sys
from pathlib import Path
info = json.loads(Path(sys.argv[1]).read_text())
commit = info.get("source_commit")
if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
    raise SystemExit("Package source commit is missing or invalid")
if sys.argv[2] and commit != sys.argv[2]:
    raise SystemExit("Package source commit differs from the requested build")
print("Package source commit:", commit)
print("Package architecture: iphoneos-arm64; install prefix: /var/jb")
PYINFO
echo "Architectures:"
lipo -archs "$DYLIB" | tee "$ROOT/arches"
grep -qw arm64 "$ROOT/arches"
echo "LC_ID_DYLIB:"
otool -D "$DYLIB"
echo "LC_LOAD_DYLIB dependencies:"
otool -L "$DYLIB"
if otool -L "$DYLIB" | grep -q FridaGadget; then echo "Unexpected Frida dependency"; exit 1; fi
echo "Rootless package Mach-O checked; Feather IPA must separately validate actual LC_LOAD_DYLIB path, nested signatures and Substrate."
