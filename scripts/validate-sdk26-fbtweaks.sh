#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?THEOS must be set}"
SDK="$THEOS/sdks/iPhoneOS26.0.sdk"
UIKIT_HEADERS="$SDK/System/Library/Frameworks/UIKit.framework/Headers"
echo "Validating SDK: $SDK"
[ -d "$SDK" ] || { echo "::error::Missing iPhoneOS26.0.sdk in $THEOS/sdks"; exit 1; }
[ -d "$UIKIT_HEADERS" ] || { echo "::error::Missing UIKit headers in iPhoneOS26.0.sdk"; exit 1; }
echo "UIKit Glass/Liquid header candidates, if exported by this SDK:"
{ grep -R "Glass\|Liquid" "$UIKIT_HEADERS" 2>/dev/null || true; } | head -80
