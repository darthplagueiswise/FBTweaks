#!/usr/bin/env python3
from pathlib import Path
import gzip, json, sys, re
root=Path(__file__).resolve().parents[1]
errors=[]
def check(c,m):
    if not c: errors.append(m)
def read(p): return (root/p).read_text(errors='ignore')

# Keep existing validation broad enough for fresh tree and patch tree.
for p in ['src/Menu/FBGRMenuTheme.m','src/Menu/FBGRGateCategoryVC.m','src/Menu/FBGRGateRuntimeBrowserVC.m','src/Menu/FBGRBoolRuntimeBrowserVC.m','src/Runtime/FBGRBoolRuntimeInventory.m','src/Hooks/FBGRMCGateHooks.xm']:
    check((root/p).exists(), f'{p} missing')

theme=read('src/Menu/FBGRMenuTheme.m')
check('FBGRApplyReadableTextCell' in theme, 'Theme must provide readable multiline cell helper')
check('numberOfLines = 0' in theme and 'NSLineBreakByCharWrapping' in theme, 'Long feature names must wrap, not truncate')
check('UIBlurEffect' not in theme, 'UI must not use UIBlurEffect fake glass')
check('UIGlassEffect' in theme or 'UILiquidGlassEffect' in theme, 'UI must try real LiquidGlass classes')

cat=read('src/Menu/FBGRGateCategoryVC.m')
mcvc=read('src/Menu/FBGRGateRuntimeBrowserVC.m')
boolvc=read('src/Menu/FBGRBoolRuntimeBrowserVC.m')
for name,src in [('category',cat),('mc runtime',mcvc),('bool runtime',boolvc)]:
    check('FBGRApplyReadableTextCell' in src, f'{name} must use readable multiline cells')
    check('UISwitch' in src and 'toggle:' in src, f'{name} must have switch toggles')
check('UITableViewCellAccessoryDisclosureIndicator' not in mcvc, 'MC runtime must use switches, not disclosure-only rows')
check('Install hook sem override' not in boolvc and 'UIAlertAction actionWithTitle:@"Force YES' not in boolvc and 'UIAlertAction actionWithTitle:@"Force NO' not in boolvc, 'Bool runtime must use toggle, not confusing force actions sheet')

mc=read('src/Hooks/FBGRMCGateHooks.xm')
# WATweaks-compatible model: startup is allowed, but only as a guarded persisted install pass.
# It must not blindly hook everything without checking persisted overrides/cache.
check('__attribute__((constructor))' in mc or '%ctor' in mc, 'MC hooks must have startup reapply path like WATweaks')
check('FBGRMCGateHooksInstallIfPersisted' in mc or 'FBGRGateAllOverrideSlotIds().count' in mc, 'MC startup path must be gated by persisted overrides')
check('dispatch_after' in mc, 'MC hooks must retry delayed after launch for late-loaded classes')
check('objc_getClassList' in mc and 'MSHookMessageEx' in mc, 'MC hooks must perform real runtime scan and hook')
check('getBool:withOptions:' in mc and 'getBool:withOptions:withDefault:' in mc, 'MC hooks must cover bool getter selectors')
check('mode=persisted startup' in mc or 'InstallIfPersisted' in mc, 'MC diagnostic must describe persisted startup behavior')

boolm=read('src/Runtime/FBGRBoolRuntimeInventory.m')
check('@implementation FBGRBoolRuntimeInventory' in boolm, 'BoolRuntime implementation context missing')
check('objc_getClassList' in boolm and 'class_getImageName' in boolm and 'class_copyMethodList' in boolm and 'method_copyReturnType' in boolm, 'Bool runtime must scan real ObjC runtime')
check('MSHookMessageEx' in boolm, 'Bool runtime must patch through MSHookMessageEx')
check('FBGRGateAllRuntimeHookSpecs' in boolm or 'FBGRGateRememberRuntimeHook' in boolm, 'Bool runtime must persist/reapply hook specs')

meta=root/'resources/runtime/ReactMobileConfigMetadata.json.gz'
if meta.exists():
    try:
        with gzip.open(meta,'rt',encoding='utf-8') as f: j=json.load(f)
        schema=j.get('schema',{})
        bools=sum(1 for v in schema.values() if isinstance(v,dict) and v.get('type')=='boolValue')
        print(f'ReactMobileConfigMetadata.json.gz: OK, {len(schema)} entries, {bools} bool params')
    except Exception as e:
        errors.append(f'metadata invalid: {e}')

if errors:
    print('FBTweaks validation failed:', file=sys.stderr)
    for e in errors: print(' - '+e, file=sys.stderr)
    sys.exit(1)
print('OK: FBTweaks WATweaks-style persisted startup hook validation passed')
