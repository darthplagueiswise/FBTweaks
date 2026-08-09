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
grep -q '^INSTALL_TARGET_PROCESSES = Messenger$' Makefile || fail "processo alvo != Messenger"
grep -q 'com.facebook.Messenger' FBTweak.plist || fail "bundle alvo != Messenger"

echo "[validate] SDK presente..."
SDK="${THEOS:-$HOME/theos}/sdks/iPhoneOS26.2.sdk"
[ -d "$SDK" ] || fail "SDK 26.2 ausente em $SDK"

echo "[validate] Headers Liquid Glass (UIKit 26)..."
UIKIT="$SDK/System/Library/Frameworks/UIKit.framework/Headers"
if [ -d "$UIKIT" ]; then
  grep -rq "UIGlassEffect" "$UIKIT" || echo "AVISO: UIGlassEffect não encontrado nos headers (UI nativa pode degradar)."
fi

if find src -type f -name "*.swift" | grep -q .; then fail "Swift ainda presente em src/"; fi

echo "[validate] Sem arquivos temporários em src/ que o find pegaria..."
BADF="$(find src -type f \( -name '*.old.m' -o -name '*.bak' -o -name '*wip*.xm' -o -name '*_backup.m' \) 2>/dev/null || true)"
[ -z "$BADF" ] || fail "arquivos temporários em src/: $BADF"

echo "[validate] Messenger 574 mapped hooks..."
grep -q '^THEOS_LAYOUT_DIR_NAME := layout-messenger$' Makefile || fail "layout Messenger isolado ausente"
grep -q 'src/MessengerTweak.m' Makefile || fail "entrypoint Messenger fora do target"
grep -q '^\$(TWEAK_NAME)_LIBRARIES = substrate$' Makefile || fail "link explícito do Substrate ausente"
if grep -q '\$(shell find src' Makefile; then fail "target Messenger ainda compila toda a branch Facebook"; fi
grep -q '_TtC25MDSModernTabBarController25MDSModernTabBarController' src/Features/Messenger/FBTMessengerFlags.m || fail "host Messenger ausente"
grep -q '0x008103fe000b1472' src/Features/Messenger/FBTMessengerFlags.m || fail "gate is_employee ausente"
grep -q '0x0081065800011c1c' src/Features/Messenger/FBTMessengerFlags.m || fail "gate Homebase ausente"
grep -q 'MSGCSessionedMobileConfigGetBoolean' src/Features/Messenger/FBTMessengerFlags.m || fail "reader Messenger ausente"
if grep -q 'MSHookFunction' src/Features/Messenger/FBTMessengerFlags.m; then fail "Messenger não pode usar hook inline em __TEXT"; fi

echo "[validate] OK"
