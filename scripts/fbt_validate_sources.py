#!/usr/bin/env python3
from pathlib import Path
import gzip, json, sys, re

root = Path(__file__).resolve().parents[1]
errors = []

def check(cond, msg):
    if not cond:
        errors.append(msg)

mf = (root / 'Makefile').read_text(errors='ignore')
check('TARGET := iphone:clang:16.2:15.0' in mf, 'Makefile target must match WATweaks iPhoneOS16.2 baseline')
check('modules/fishhook/fishhook.c' in mf, 'Makefile must build vendored fishhook.c')
check('resources/runtime/*.json.gz' in mf, 'Makefile must stage gz runtime JSON metadata')
check('INSTALL_TARGET_PROCESSES = Facebook' in mf, 'Makefile must target Facebook process')

plist = (root / 'FBTweaks.plist').read_text(errors='ignore')
check('com.facebook.Facebook' in plist, 'FBTweaks.plist must filter com.facebook.Facebook')

for f in ['modules/fishhook/fishhook.c','modules/fishhook/fishhook.h','build.sh','build-fast.sh','.github/workflows/build-fbtweaks.yml']:
    check((root / f).exists(), f'{f} missing')

# Objective-C .m files must not contain C++ linkage syntax.
for p in root.glob('src/**/*.m'):
    txt = p.read_text(errors='ignore')
    check('extern "C"' not in txt, f'{p.relative_to(root)} contains extern "C" but is compiled as .m')
    check('@property(nonatomic, strong) dispatch_once_t' not in txt, f'{p.relative_to(root)} has invalid strong dispatch_once_t property')

# Core entrypoints expected by Tweak.x
for p in ['src/Hooks/FBGRLiquidGlassHooks.xm','src/Hooks/FBGRMCGateHooks.xm']:
    check((root / p).exists(), f'{p} missing')

tw = (root / 'src/Tweak.x').read_text(errors='ignore')
check('FBGRLiquidGlassEnsureInstalled' in tw, 'Tweak.x does not initialize LiquidGlass hook')
check('FBGRMCGateHooksEnsureInstalled' in tw, 'Tweak.x does not initialize MC gate hooks')
check('UILongPressGestureRecognizer' in tw and 'numberOfTouchesRequired = 2' in tw, 'Tweak.x must include two-finger long press menu gesture')

meta = root / 'resources/runtime/ReactMobileConfigMetadata.json.gz'
check(meta.exists(), 'ReactMobileConfigMetadata.json.gz missing')
if meta.exists():
    try:
        with gzip.open(meta, 'rt', encoding='utf-8') as f:
            j = json.load(f)
        schema = j.get('schema', {})
        bool_count = sum(1 for v in schema.values() if isinstance(v, dict) and v.get('type') == 'boolValue')
        check(len(schema) >= 5300, f'ReactMobileConfigMetadata schema too small: {len(schema)}')
        check(bool_count >= 4600, f'ReactMobileConfigMetadata bool count too small: {bool_count}')
        print(f'ReactMobileConfigMetadata.json.gz: OK, {len(schema)} entries, {bool_count} bool params')
    except Exception as e:
        errors.append(f'ReactMobileConfigMetadata.json.gz invalid: {e}')

if errors:
    print('FBTweaks validation failed:', file=sys.stderr)
    for e in errors:
        print(' - ' + e, file=sys.stderr)
    sys.exit(1)
print('OK: FBTweaks base validation passed')
