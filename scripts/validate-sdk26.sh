#!/usr/bin/env bash
#
# validate-sdk26.sh — checa pré-condições do build antes de compilar.
# Roda no CI antes de ./build.sh para falhar cedo.
#
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "VALIDATION FAIL: $1"; exit 1; }

echo "[validate] Makefile target/arch..."
grep -q 'TARGET := iphone:clang:26.2:16.3' Makefile || fail "TARGET errado no Makefile"
grep -q '^ARCHS = arm64$' Makefile || fail "ARCHS != arm64"

echo "[validate] SDK presente..."
SDK="${THEOS:-$HOME/theos}/sdks/iPhoneOS26.2.sdk"
[ -d "$SDK" ] || fail "SDK 26.2 ausente em $SDK"

echo "[validate] Headers Liquid Glass (UIKit 26)..."
UIKIT="$SDK/System/Library/Frameworks/UIKit.framework/Headers"
if [ -d "$UIKIT" ]; then
  grep -rq "UIGlassEffect" "$UIKIT" || echo "AVISO: UIGlassEffect não encontrado nos headers (UI nativa pode degradar)."
fi

echo "[validate] Assets de bundle presentes..."
[ -f "layout/Library/Application Support/FBTweak.bundle/FBTFlags.json" ] || fail "FBTFlags.json ausente no layout"
[ -f "layout/Library/Application Support/FBTweak.bundle/FBTHeadlineFlags.json" ] || fail "FBTHeadlineFlags.json ausente no layout"
[ -d "layout/Library/Application Support/FBTweak.bundle/QueryConfigs" ] || fail "QueryConfigs dir ausente no layout"
if find src -type f -name "*.swift" | grep -q .; then fail "Swift ainda presente em src/"; fi

echo "[validate] Sem arquivos temporários em src/ que o find pegaria..."
BADF="$(find src -type f \( -name '*.old.m' -o -name '*.bak' -o -name '*wip*.xm' -o -name '*_backup.m' \) 2>/dev/null || true)"
[ -z "$BADF" ] || fail "arquivos temporários em src/: $BADF"

echo "[validate] Runtime files..."
grep -q "MSGCSessionedMobileConfigGetBoolean" src/Runtime/FBTMobileConfigRuntime.m || fail "MobileConfig runtime sem MSGC bool hook"
grep -q "MSHookMessageEx" src/Runtime/FBTRuntimeBoolBrowser.m || fail "Runtime BOOL sem MSHookMessageEx"
grep -q "configureWithDefaultBackground" src/Settings/FBTSettingsViewController.m || fail "UI UIKit sem default Liquid Glass appearance"

echo "[validate] OK"
