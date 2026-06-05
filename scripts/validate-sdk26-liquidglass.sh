#!/usr/bin/env bash
set -euo pipefail
: "${THEOS:?THEOS must be set}"
SDK_VERSION="${SDK_VERSION:-26.2}"
SDK="$THEOS/sdks/iPhoneOS${SDK_VERSION}.sdk"
UIKIT_HEADERS="$SDK/System/Library/Frameworks/UIKit.framework/Headers"
echo "Validating SDK: $SDK"
[ -d "$SDK" ] || { echo "::error::Missing iPhoneOS${SDK_VERSION}.sdk in $THEOS/sdks"; exit 1; }
[ -d "$UIKIT_HEADERS" ] || { echo "::error::Missing UIKit headers in iPhoneOS${SDK_VERSION}.sdk"; exit 1; }
echo "UIKit Glass/Liquid header candidates, if exported by this SDK:"
{ grep -R "Glass\|Liquid" "$UIKIT_HEADERS" 2>/dev/null || true; } | head -100
