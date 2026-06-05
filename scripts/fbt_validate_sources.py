#!/usr/bin/env python3
from pathlib import Path
import gzip, json, sys, re
root=Path(__file__).resolve().parents[1]
errors=[]
def check(c,m):
    if not c: errors.append(m)
def strip_comments(s):
    s=re.sub(r'/\*.*?\*/','',s,flags=re.S)
    s=re.sub(r'//.*','',s)
    return s
def function_body(src,name):
    m=re.search(r'\b(?:BOOL|void|NSArray<NSNumber \*> \*)\s+'+re.escape(name)+r'\s*\([^)]*\)\s*\{',src)
    if not m: return ''
    i=m.end(); depth=1; j=i
    while j < len(src) and depth:
        if src[j]=='{': depth+=1
        elif src[j]=='}': depth-=1
        j+=1
    return src[i:j-1]
mf=(root/'Makefile').read_text(errors='ignore')
check('26.2' in mf and 'iPhoneOS26.2.sdk' in mf, 'Makefile must target SDK26.2')
check('-fuse-ld=lld' not in mf, 'Makefile must not force lld')
check('-include src/FBGramPrefix.h' not in mf, 'Makefile must not force ObjC prefix into fishhook.c')
check('modules/fishhook/fishhook.c' in mf, 'fishhook.c missing from Makefile')
check('substrate z' in mf, 'Makefile must link substrate and zlib')
wf=(root/'.github/workflows/buildtweak.yml')
check(wf.exists(), 'buildtweak.yml missing')
if wf.exists():
    wt=wf.read_text(errors='ignore'); check('iPhoneOS26.2.sdk' in wt and 'experiments' in wt, 'workflow must build experiments with SDK26.2')
for f in ['build.sh','build-fast.sh','scripts/validate-sdk26-liquidglass.sh','modules/fishhook/fishhook.c','modules/fishhook/fishhook.h']:
    check((root/f).exists(), f'{f} missing')

tw=(root/'src/Tweak.x').read_text(errors='ignore')
check('%hook FDSTouchStateAnnouncingControl' in tw and '%hook FBTabBarItemDefaultView' in tw, 'Tweak.x must keep exact working tab button hooks')
check('%hook UIWindow' not in tw and '%hook UIViewController' not in tw, 'Tweak.x must not install broad global UIKit hooks')
check('%ctor' not in tw and '__attribute__((constructor))' not in tw, 'Tweak.x must not run constructor/startup work')
check('FBGRLiquidGlassEnsureInstalled' not in tw, 'Tweak.x must not install LiquidGlass at startup')
check('FBGRMCGateHooksEnsureInstalled' not in tw and 'FBGRGateWarmCacheFromPrefs' not in tw, 'Tweak.x must not install or warm MobileConfig at startup')
check('numberOfTouchesRequired = 2' not in tw and 'numberOfTouchesRequired = 3' not in tw, 'Tweak.x must not use global multi-finger gesture')

cat=(root/'src/Runtime/FBGRMCCatalog.m').read_text(errors='ignore')
check('NSBundle.mainBundle.bundlePath' in cat and 'Facebook.app/ReactMobileConfigMetadata.json' in cat, 'catalog must prefer live Facebook.app metadata')
check('FBGRGunzip' in cat, 'catalog must read json.gz')
reg=(root/'src/Runtime/FBGRGateRegistry.m').read_text(errors='ignore')
check('METAIsLiquidGlassEnabled' not in reg and 'slot 0' not in reg and '_METAIsLiquidGlassEnabled' not in reg, 'registry must not expose fake old LiquidGlass slot')
check('FBGRFlagsFor' in reg and '[[FBGRMCCatalog shared] boolParams]' in reg, 'registry must be generated from runtime catalog')
catvc=(root/'src/Menu/FBGRGateCategoryVC.m').read_text(errors='ignore')
check('kFBGRLiquidGlassMaster' not in catvc and 'flag.slotId == 0' not in catvc, 'category VC must not special-case fake LiquidGlass slot0')
mc=(root/'src/Hooks/FBGRMCGateHooks.xm').read_text(errors='ignore')
check('__attribute__((constructor))' not in mc, 'MC hooks must not install in constructor')
obs = (root / 'src/Hooks/FBGRMCPropsObserver.xm').read_text(errors='ignore')
check('__attribute__((constructor))' not in obs, 'Observer must not install from constructor')
check('FBGRMCObserverSetEnabled' in obs, 'Observer must install only when enabled from menu')
check('objc_copyClassList' not in mc, 'MC hooks must not global scan')
check('NSStringFromClass([self class])' not in mc, 'MC hot path must not allocate class NSString')
check('FBGRLogAppend(msg)' not in mc, 'MC hot path must not log')
store=(root/'src/Runtime/FBGRGateStore.m').read_text(errors='ignore')
check('FBGRGateEntry gEntries' in store, 'GateStore must use RAM cache for hot path')
store_nc=strip_comments(store)
is_body=function_body(store_nc,'FBGRGateIsSet')
get_body=function_body(store_nc,'FBGRGateGet')
check(is_body and get_body, 'GateStore must define FBGRGateIsSet and FBGRGateGet')
for forbidden in ['NSUserDefaults','FBGRPrefs','NSString','FBGRGateWarmCacheFromPrefs','dictionaryRepresentation','synchronize']:
    check(forbidden not in is_body and forbidden not in get_body, f'GateStore hot path must not use {forbidden}')
theme=(root/'src/Menu/FBGRMenuTheme.m').read_text(errors='ignore')
check('UIBlurEffect' not in theme and 'FBGRCreateRealGlassEffect' in theme, 'menu theme must use real UIKit glass only, not blur simulation')
boolh=(root/'src/Runtime/FBGRBoolRuntimeInventory.h').read_text(errors='ignore') if (root/'src/Runtime/FBGRBoolRuntimeInventory.h').exists() else ''
boolm=(root/'src/Runtime/FBGRBoolRuntimeInventory.m').read_text(errors='ignore') if (root/'src/Runtime/FBGRBoolRuntimeInventory.m').exists() else ''
boolvc=(root/'src/Menu/FBGRBoolRuntimeBrowserVC.m').read_text(errors='ignore') if (root/'src/Menu/FBGRBoolRuntimeBrowserVC.m').exists() else ''
surf=(root/'src/Menu/FBGRSurfaceListVC.m').read_text(errors='ignore')
check('FBGRBoolRuntimeImageKindExecutable' in boolh and 'FBGRBoolRuntimeImageKindFBSharedFramework' in boolh, 'Bool Runtime must expose executable + FBSharedFramework image kinds')
check('class_getImageName' in boolm and 'objc_copyClassList' in boolm and 'MSHookMessageEx' in boolm, 'Bool Runtime must scan real ObjC runtime and hook via MSHookMessageEx')
check('method_getNumberOfArguments(m) != 2' in boolm and 'method_copyReturnType' in boolm, 'Bool Runtime must filter no-arg BOOL methods')
check('/FBSharedFramework.framework/FBSharedFramework' in boolm and '/Facebook.app/Facebook' in boolm, 'Bool Runtime must filter exact executable/framework images')
check('Force YES' in boolvc and 'Force NO' in boolvc, 'Bool Runtime browser must expose YES/NO patch actions')
check('FBGRRootSectionBoolRT' in surf and 'Executable Bool Runtime' in surf and 'FBSharedFramework Bool Runtime' in surf, 'SurfaceList must expose both real Bool Runtime browsers')
check((root/'docs/RUNTIME_BOOL_BROWSER.md').exists(), 'Bool Runtime docs missing')
meta=root/'resources/runtime/ReactMobileConfigMetadata.json.gz'
if meta.exists():
    try:
        with gzip.open(meta,'rt',encoding='utf-8') as f: j=json.load(f)
        schema=j.get('schema',{}); bools=sum(1 for v in schema.values() if isinstance(v,dict) and v.get('type')=='boolValue')
        print(f'ReactMobileConfigMetadata.json.gz: OK, {len(schema)} entries, {bools} bool params')
    except Exception as e: errors.append(f'metadata invalid: {e}')
else: errors.append('metadata gzip missing')
if errors:
    print('FBTweaks validation failed:', file=sys.stderr)
    for e in errors: print(' - '+e, file=sys.stderr)
    sys.exit(1)
print('OK: FBTweaks SDK26.2 startup-safe runtime validation passed')
