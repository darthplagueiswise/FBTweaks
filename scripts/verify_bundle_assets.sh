#!/usr/bin/env bash
set -euo pipefail

BUNDLE="${1:?usage: verify_bundle_assets.sh BUNDLE_DIR [--nonempty]}"
NONEMPTY=0
case "${2:-}" in
  '') ;;
  --nonempty) NONEMPTY=1 ;;
  *) echo "Unknown asset validation option: $2" >&2; exit 2 ;;
esac

for ASSET in FBTFlags.json FBTHeadlineFlags.json; do
  if { [ "$NONEMPTY" -eq 0 ] && [ ! -f "$BUNDLE/$ASSET" ]; } ||
     { [ "$NONEMPTY" -eq 1 ] && [ ! -s "$BUNDLE/$ASSET" ]; }; then
    echo "Required bundle file missing or invalid: $BUNDLE/$ASSET" >&2
    exit 1
  fi
done
for DIRECTORY in QueryConfigs; do
  if [ ! -d "$BUNDLE/$DIRECTORY" ]; then
    echo "Required bundle directory missing: $BUNDLE/$DIRECTORY" >&2
    exit 1
  fi
done
