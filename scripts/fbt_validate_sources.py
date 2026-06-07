#!/usr/bin/env python3
from pathlib import Path
import gzip, json, sys, re
root = Path(__file__).resolve().parents[1]
errors = []
def check(c, m):
    if not c: errors.append(m)
def read(p): return (root / p).read_text(errors='ignore')
def strip_comments(s):
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    s = re.sub(r'//.*', '', s)
    return s

mf = read('Makefile')
check('TARGET := iphone:clang:26.2:16.3' in mf or 'TARGET := iphone:clang:26.0:16.3' in mf, 'Makefile must target SDK26.2 or fallback SDK26.0')
check('-fuse-ld=lld' not in mf, 'Makefile must not force lld')
check('-include src/FBGramPrefix.h' not in mf, 'Makefile must not force ObjC prefix into fishhook.c')
check('modules/fishhook/fishhook.c' in mf, 'Makefile must compile fishhook.c')
check('substrate z' in mf, 'Makefile must link substrate and z')
check((root / '.github/workflows/buildtweak.yml').exists(), 'workflow missing')

for f in ['modules/fishhook/fishhook.c', 'modules/fishhook/fishhook.h', 'build.sh', 'build-fast.sh', 'scripts/validate-sdk26-liquidglass.sh']:
    check((root / f).exists(), f'{f} missing')

tw = read('src/Tweak.x')
check('%hook FDSTouchStateAnnouncingControl' in tw and '%hook FBTabBarItemDefaultView' in tw, 'Tweak.x must keep working exact tab longpress hooks')
for bad in ['%hook UIWindow', '%hook UIViewController', 'FBGRLiquidGlassEnsureInstalled', 'FBGRGateWarmCacheFromPrefs', 'FBGRMCGateHooksApplyPersistedOverrides', 'FBGRDogFoodSetEnabled', 'dispatch_after', 'fishhook', 'rebind_symbols']:
    check(bad not in tw, f'Tweak.x must not contain startup/global work: {bad}')

cat = read('src/Runtime/FBGRMCCatalog.m')
check('NSBundle.mainBundle.bundlePath' in cat and 'Facebook.app/ReactMobileConfigMetadata.json' in cat, 'Catalog must prefer live Facebook.app metadata')
check('paramForFullKey' in cat and 'slotIdForKey' in cat, 'Catalog must resolve key string to slotId')
for c in ['FBGRFeatureCategoryUI','FBGRFeatureCategoryLiquidGlass','FBGRFeatureCategoryTabBar','FBGRFeatureCategoryDating','FBGRFeatureCategoryDogfood','FBGRFeatureCategoryInternal','FBGRFeatureCategoryDebug']:
    check(c in cat, f'Catalog missing {c}')

store = read('src/Runtime/FBGRGateStore.m')
check('FBGRGateEntry gEntries' in store, 'GateStore must be RAM cache backed')
for name in ['FBGRGateIsSet', 'FBGRGateGet']:
    m = re.search(r'BOOL\s+' + name + r'\s*\([^)]*\)\s*\{([^{}]*)\}', store, re.S)
    check(m is not None, f'{name} missing')
    if m:
        body = strip_comments(m.group(1))
        for bad in ['NSUserDefaults', 'FBGRPrefs', 'NSString', 'WarmCache', 'dictionaryRepresentation', 'synchronize']:
            check(bad not in body, f'{name} hot path must not use {bad}')

mc = read('src/Hooks/FBGRMCGateHooks.xm')
check('__attribute__((constructor))' not in mc and '%ctor' not in mc, 'MC hooks must not install at startup')
check('objc_getClassList' in mc and 'class_getImageName' in mc and 'class_copyMethodList' in mc, 'MC hooks must scan runtime on demand')
check('rebind_symbols' in mc and '__ZN12mobileconfig14getBoolDefaultEy' in mc and '__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc' in mc, 'MC hooks must include fishhook C/C++ bool bridges')
for sel in ['getBool:', 'getBool:withDefault:', 'getBool:withOptions:', 'getBool:withOptions:withDefault:', 'getBoolWithoutLogging:', 'getBoolForParam:withDefault:', 'ig_boolForKey:']:
    check(sel in mc, f'MC hook missing selector {sel}')

lg = read('src/Hooks/FBGRLiquidGlassHooks.xm')
check('__attribute__((constructor))' not in lg and '%ctor' not in lg, 'LiquidGlass must not install at startup')
check('IGLiquidGlassExperimentHelper' in lg and 'MSHookMessageEx' in lg, 'LiquidGlass must use real helper hooks')

theme = read('src/Menu/FBGRMenuTheme.m')
check('UIBlurEffect' not in theme, 'UI must not simulate LiquidGlass with UIBlurEffect')
check('UIGlassEffect' in theme and 'UILiquidGlassEffect' in theme, 'UI must attempt real UIKit LiquidGlass classes')
check('numberOfLines = 0' in theme and 'UIListContentConfiguration' in theme, 'Cells must show full feature names')

boolm = read('src/Runtime/FBGRBoolRuntimeInventory.m')
check('@implementation FBGRBoolRuntimeInventory' in boolm, 'Bool runtime implementation context missing')
check('objc_getClassList' in boolm and 'class_getImageName' in boolm and 'class_copyMethodList' in boolm and 'method_copyReturnType' in boolm, 'Bool runtime must scan real ObjC runtime')
check('/Facebook.app/Facebook' in boolm and '/FBSharedFramework.framework/FBSharedFramework' in boolm, 'Bool runtime must filter executable and FBShared images')
check('MSHookMessageEx' in boolm, 'Bool runtime must patch with MSHookMessageEx')

for vc in ['src/Menu/FBGRGateCategoryVC.m','src/Menu/FBGRGateRuntimeBrowserVC.m','src/Menu/FBGRBoolRuntimeBrowserVC.m']:
    t = read(vc)
    check('UISwitch' in t and 'FBGRConfigureSwitchCell' in t, f'{vc} must have direct toggles')
    check('Force YES' in t or 'FORÇADO' in t or 'FORCE YES' in t, f'{vc} must show force state')

surf = read('src/Menu/FBGRSurfaceListVC.m')
for label in ['MobileConfig Runtime Browser','Executable Bool Runtime','FBSharedFramework Bool Runtime','Instalar/Recarregar hooks MobileConfig']:
    check(label in surf, f'Surface missing {label}')

meta = root / 'resources/runtime/ReactMobileConfigMetadata.json.gz'
try:
    with gzip.open(meta, 'rt', encoding='utf-8') as f:
        j = json.load(f)
    schema = j.get('schema', {})
    bools = sum(1 for v in schema.values() if isinstance(v, dict) and v.get('type') == 'boolValue')
    print(f'ReactMobileConfigMetadata.json.gz: OK, {len(schema)} entries, {bools} bool params')
    check(len(schema) == 5377 and bools == 4679, 'metadata must be current ReactMobileConfigMetadata(7)')
except Exception as e:
    errors.append(f'metadata invalid: {e}')

if errors:
    print('FBTweaks validation failed:', file=sys.stderr)
    for e in errors: print(' - ' + e, file=sys.stderr)
    sys.exit(1)

print('OK: FBTweaks v3 real hooks, toggles and full-name UI validation passed')
