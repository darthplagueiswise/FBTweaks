#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?THEOS must be set}"
SDK="$THEOS/sdks/iPhoneOS26.2.sdk"
[ -d "$SDK" ] || SDK="$THEOS/sdks/iPhoneOS26.0.sdk"
[ -d "$SDK" ] || { echo "Missing iPhoneOS26.2/26.0 SDK"; exit 1; }
echo "Validating SDK: $SDK"
find "$SDK/System/Library/Frameworks/UIKit.framework/Headers" -maxdepth 1 -type f \( -name '*Glass*' -o -name '*Effect*' \) | head -60 || true
