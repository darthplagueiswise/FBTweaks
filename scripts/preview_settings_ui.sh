#!/usr/bin/env bash
# Usage: bash scripts/preview_settings_ui.sh [artifact-directory]
# Real UIKit helper/catalog preview; this does not validate injected Facebook UI.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_root/test-results/settings-preview}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
# Never leave stale screenshots behind when a later run must skip.
rm -f "$output_dir"/*.png "$output_dir"/*-result.json "$output_dir/SKIPPED.txt"
if ! command -v xcrun >/dev/null 2>&1; then
  printf 'SKIPPED: Xcode and an iOS simulator runtime are required.\n' | tee "$output_dir/SKIPPED.txt"
  exit 0
fi
xcrun simctl list -j > "$output_dir/simulators.json"
python3 - "$output_dir/simulators.json" > "$output_dir/selection.txt" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
runtimes = [r for r in state.get('runtimes', []) if r.get('isAvailable') and '.iOS-' in r['identifier']]
runtimes.sort(key=lambda r: (r.get('version', '').startswith('26.'), tuple(map(int, r.get('version', '0').split('.')))), reverse=True)
if runtimes:
    runtime = runtimes[0]
    version = tuple(map(int, runtime.get('version', '0').split('.')))
    version_value = version[0] * 65536 + (version[1] if len(version) > 1 else 0) * 256
    devices = [d for d in state.get('devicetypes', []) if 'iPhone' in d['name'] and d.get('minRuntimeVersion', 0) <= version_value <= d.get('maxRuntimeVersion', 2**32-1)]
    if devices: print(runtime['identifier'], devices[-1]['identifier'])
PY
if [[ ! -s "$output_dir/selection.txt" ]]; then
  printf 'SKIPPED: No compatible installed iOS runtime and iPhone device type. No screenshots generated.\n' | tee "$output_dir/SKIPPED.txt"
  exit 0
fi
read -r runtime_id device_type < "$output_dir/selection.txt"
app_dir="$output_dir/FBTStylePreview.app"
mkdir -p "$app_dir"
sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
if [[ "$arch" == arm64 ]]; then platform_target=arm64-apple-ios16.3-simulator; else platform_target=x86_64-apple-ios16.3-simulator; fi
xcrun --sdk iphonesimulator clang -target "$platform_target" -isysroot "$sdk_path" -fobjc-arc -DFBT_BUILD_NUMBER="${GITHUB_RUN_NUMBER:-0}" -Werror=unguarded-availability-new -Wno-deprecated-declarations \
  -I "$repo_root/src" -I "$repo_root/src/UI" -I "$repo_root/src/Settings" \
  "$repo_root/src/UI/FBTUIKit26LiquidGlass.m" "$repo_root/src/Settings/FBTSettingsCatalog.m" "$repo_root/src/Settings/FBTSettingsPresentation.m" "$repo_root/src/FBTDefaults.m" "$repo_root/tests/preview/SettingsPreview.m" \
  -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -o "$app_dir/FBTStylePreview"
cat > "$app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.fbtweaks.StylePreview</string>
<key>CFBundleExecutable</key><string>FBTStylePreview</string>
<key>CFBundleName</key><string>FBTStylePreview</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>MinimumOSVersion</key><string>16.3</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
simulator_id="$(xcrun simctl create "FBT settings preview $$" "$device_type" "$runtime_id")"
cleanup() {
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$app_dir"
# The disposable simulator starts with accessibility defaults. Verify those in
# the first three variants instead of paying for an unnecessary initial reboot.
# Increase Contrast has a supported simctl UI command. Reduce Transparency uses
# its actual AX-domain key and a restart; public UIKit API assertions below are
# authoritative, so an ignored preference remains a test failure.
xcrun simctl help ui > "$output_dir/simctl-ui-help.txt"
for variant in light dark accessibility high-contrast reduce-transparency; do
  contrast=disabled
  if [[ "$variant" == high-contrast ]]; then contrast=enabled; fi
  xcrun simctl ui "$simulator_id" increase_contrast "$contrast"
  if [[ "$variant" == reduce-transparency ]]; then
    xcrun simctl spawn "$simulator_id" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool YES
    xcrun simctl spawn "$simulator_id" defaults read com.apple.Accessibility > "$output_dir/accessibility-preferences.txt"
    xcrun simctl shutdown "$simulator_id"
    xcrun simctl boot "$simulator_id"
    xcrun simctl bootstatus "$simulator_id" -b
  fi
  appearance=light
  if [[ "$variant" == dark ]]; then appearance=dark; fi
  xcrun simctl ui "$simulator_id" appearance "$appearance"
  if [[ "$variant" == accessibility ]]; then xcrun simctl ui "$simulator_id" content_size accessibility-extra-extra-extra-large; else xcrun simctl ui "$simulator_id" content_size large; fi
  for category in root network; do
    xcrun simctl terminate "$simulator_id" dev.fbtweaks.StylePreview 2>/dev/null || true
    container="$(xcrun simctl get_app_container "$simulator_id" dev.fbtweaks.StylePreview data)"
    rm -f "$container/Documents/style-result.json"
    preview_category="$category"
    if [[ "$category" == root ]]; then preview_category=""; fi
    SIMCTL_CHILD_FBT_PREVIEW_CATEGORY="$preview_category" SIMCTL_CHILD_FBT_PREVIEW_VARIANT="$variant" xcrun simctl launch "$simulator_id" dev.fbtweaks.StylePreview
    for attempt in {1..30}; do
      if [[ -f "$container/Documents/style-result.json" ]]; then break; fi
      sleep 1
    done
    cp "$container/Documents/style-result.json" "$output_dir/$category-$variant-result.json"
    python3 - "$output_dir/$category-$variant-result.json" "$variant" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result['accessibilityVariant'] == sys.argv[2], result
assert result['reduceTransparency'] == (sys.argv[2] == 'reduce-transparency'), result
assert result['increasedContrast'] == (sys.argv[2] == 'high-contrast'), result
assert not result['failures'], result
print('Production UIKit helper/catalog checks passed:', result)
PY
    xcrun simctl io "$simulator_id" screenshot "$output_dir/$category-$variant.png"
  done
done
printf 'Real UIKit helper/catalog screenshots: %s\n' "$output_dir"
