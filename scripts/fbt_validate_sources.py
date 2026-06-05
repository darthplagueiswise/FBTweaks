#!/usr/bin/env python3
from pathlib import Path
import gzip, json, sys, re
root=Path(__file__).resolve().parents[1]
errors=[]
def check(c,m):
    if not c: errors.append(m)
def read(p): return (root/p).read_text(errors='ignore')

mf=read('Makefile')
check('TARGET := iphone:clang:26.2:16.3' in mf or 'TARGET := iphone:clang:26.0:16.3' in mf, 'Makefile must target SDK26.2 or fallback SDK26.0')
check('-fuse-ld=lld' not in mf, 'Makefile must not force lld')
check('-include src/FBGramPrefix.h' not in mf, 'Makefile must not force ObjC prefix into fishhook.c')
check('make package' in read('build.sh'), 'build.sh must generate .deb through make package')
check((root/'.github/workflows/buildtweak.yml').exists(), 'buildtweak workflow missing')

for f in ['modules/fishhook/fishhook.c','modules/fishhook/fishhook.h','resources/runtime/ReactMobileConfigMetadata.json.gz']:
    check((root/f).exists(), f'{f} missing')

tw=read('src/Tweak.x')
check('%hook FDSTouchStateAnnouncingControl' in tw and '%hook FBTabBarItemDefaultView' in tw, 'Tweak.x must keep working exact tab button longpress hooks')
for bad in ['%hook UIWindow','%hook UIViewController','FBGRLiquidGlassEnsureInstalled','FBGRGateStoreWarmup','FBGRMCGateHooksApplyPersistedOverrides','FBGRDogFoodApplyPersistentState','dispatch_after','FBGRScanAllWindowsForExactTabButton']:
    check(bad not in tw, f'Tweak.x must not contain startup/global work: {bad}')

cat=read('src/Runtime/FBGRMCCatalog.m')
check('NSBundle.mainBundle.bundlePath' in cat and 'Facebook.app/ReactMobileConfigMetadata.json' in cat, 'MC catalog must prefer live Facebook.app metadata')
check('FBGRFeatureCategoryLiquidGlass' in cat and 'FBGRFeatureCategoryDating' in cat and 'FBGRFeatureCategoryDogfood' in cat, 'MC catalog must categorize features')

store=read('src/Runtime/FBGRGateStore.m')
check('FBGRGateEntry gEntries' in store, 'GateStore must use RAM cache')
for name in ['FBGRGateIsSet','FBGRGateGet']:
    m=re.search(r'BOOL\s+'+name+r'\s*\([^)]*\)\s*\{([^{}]*)\}', store, re.S)
    check(m is not None, f'{name} missing')
    if m:
        body=m.group(1)
        for bad in ['NSUserDefaults','FBGRPrefs','NSString','WarmCache','dictionaryRepresentation','synchronize']:
            check(bad not in body, f'{name} hot path must not use {bad}')

mc=read('src/Hooks/FBGRMCGateHooks.xm')
check('__attribute__((constructor))' not in mc and '%ctor' not in mc, 'MC hooks must not install at startup')
check('objc_getClassList' not in mc and 'objc_copyClassList' not in mc, 'MC hooks must not global scan')
check('FBMobileConfigContextManager' in mc and 'FBMobileConfigSessionlessContextManager' in mc, 'MC hooks must use validated static owners')

lg=read('src/Hooks/FBGRLiquidGlassHooks.xm')
check('__attribute__((constructor))' not in lg and '%ctor' not in lg, 'LiquidGlass hooks must not install at startup')
check('IGLiquidGlassExperimentHelper' in lg and 'MSHookMessageEx' in lg, 'LiquidGlass helpers must be real MSHookMessageEx hooks')

theme=read('src/Menu/FBGRMenuTheme.m')
check('UIBlurEffect' not in theme, 'UI must not simulate LiquidGlass with UIBlurEffect')
check('UIGlassEffect' in theme or 'UILiquidGlassEffect' in theme, 'UI must attempt real UIKit LiquidGlass classes')

boolm=read('src/Runtime/FBGRBoolRuntimeInventory.m')
check('objc_getClassList' in boolm and 'class_getImageName' in boolm and 'class_copyMethodList' in boolm, 'Bool runtime must scan real ObjC runtime')
check('method_getNumberOfArguments(m) != 2' in boolm and 'method_copyReturnType' in boolm, 'Bool runtime must filter no-arg BOOL methods')
check('/Facebook.app/Facebook' in boolm and '/FBSharedFramework.framework/FBSharedFramework' in boolm, 'Bool runtime must filter exact executable/framework images')
check('MSHookMessageEx' in boolm and 'Force YES' in read('src/Menu/FBGRBoolRuntimeBrowserVC.m') and 'Force NO' in read('src/Menu/FBGRBoolRuntimeBrowserVC.m'), 'Bool runtime must patch via MSHookMessageEx and expose YES/NO')

surf=read('src/Menu/FBGRSurfaceListVC.m')
for label in ['MobileConfig Runtime Browser','Executable Bool Runtime','FBSharedFramework Bool Runtime','UI','LiquidGlass','TabBar','Namoro','DogFood','Internal','Debug Menus']:
    check(label in surf or label in read('src/FBGramPrefix.h'), f'Menu missing {label}')

meta=root/'resources/runtime/ReactMobileConfigMetadata.json.gz'
try:
    with gzip.open(meta,'rt',encoding='utf-8') as f: j=json.load(f)
    schema=j.get('schema',{})
    bools=sum(1 for v in schema.values() if isinstance(v,dict) and v.get('type')=='boolValue')
    print(f'ReactMobileConfigMetadata.json.gz: OK, {len(schema)} entries, {bools} bool params')
    check(len(schema)==5377 and bools==4679, 'metadata must be current ReactMobileConfigMetadata(7)')
except Exception as e:
    errors.append(f'metadata invalid: {e}')

if errors:
    print('FBTweaks validation failed:', file=sys.stderr)
    for e in errors: print(' - '+e, file=sys.stderr)
    sys.exit(1)
print('OK: FBTweaks fresh SDK26 runtime/LiquidGlass validation passed')
