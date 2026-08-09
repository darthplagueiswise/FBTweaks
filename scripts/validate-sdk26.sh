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
grep -q 'FBTMessengerMCParameterDescriptor' src/Features/Messenger/FBTMessengerFlags.m || fail "ABI de descritor do reader C ausente"
grep -q 'parameter ? parameter->rawValue' src/Features/Messenger/FBTMessengerFlags.m || fail "reader C não extrai a key em +16 do descritor"
grep -q 'offsetof(FBTMessengerMCParameterDescriptor, rawValue) == 16' src/Features/Messenger/FBTMessengerFlags.m || fail "offset da key MobileConfig não validado"
grep -q 'FBMobileConfigContextManager' src/Features/Messenger/FBTMessengerFlags.m || fail "reader ObjC interno do MC ausente"
grep -q 'FBMobileConfigSessionlessContextManager' src/Features/Messenger/FBTMessengerFlags.m || fail "reader sessionless do MC ausente"
grep -q 'FBMobileConfigUserSessionContextManager' src/Features/Messenger/FBTMessengerFlags.m || fail "reader sessioned ObjC do MC ausente"
grep -q 'FBTMessengerDirectInstanceMethod' src/Features/Messenger/FBTMessengerFlags.m || fail "validação de método direto ausente"
if grep -q 'FBTMessengerMCObjectDescriptor' src/Features/Messenger/FBTMessengerFlags.m; then fail "lookup de trampoline por receiver reintroduz recursão"; fi
mc_original_slots="$(grep -o '&sMC[A-Za-z]*Original' src/Features/Messenger/FBTMessengerFlags.m | sort -u | wc -l | tr -d ' ')"
[ "$mc_original_slots" -eq 10 ] || fail "cada reader MC precisa de um trampoline original próprio"
if grep -q 'MSHookFunction' src/Features/Messenger/FBTMessengerFlags.m; then fail "Messenger não pode usar hook inline em __TEXT"; fi

echo "[validate] Native iOS 26 context-menu morph..."
grep -q 'UIContextMenuInteraction' src/UI/FBTMessengerQuickMenu.m || fail "context menu nativo ausente"
grep -q 'UITargetedPreview' src/UI/FBTMessengerQuickMenu.m || fail "target do morph nativo ausente"
grep -q 'hitTest:location withEvent:nil' src/UI/FBTMessengerQuickMenu.m || fail "morph não usa o controle real sob o toque"
grep -q 'UIMenuElementAttributesKeepsMenuPresented' src/UI/FBTMessengerQuickMenu.m || fail "menu multi-toggle ausente"
if grep -q 'panel\.alpha\|animateWithDuration' src/UI/FBTMessengerQuickMenu.m; then fail "fade customizado ainda presente no quick menu"; fi
if grep -q 'UIVisualEffectView\|UIPreviewTarget\|FBTUIKit26GlassEffect' src/UI/FBTMessengerQuickMenu.m; then fail "preview de bolha artificial ainda presente"; fi
if grep -q 'src/UI/FBTUIKit26LiquidGlass.m' Makefile; then fail "helper de vidro customizado ainda está no target Messenger"; fi

echo "[validate] OK"
