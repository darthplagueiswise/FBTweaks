#!/usr/bin/env python3
from pathlib import Path
import gzip, json, sys, re
root=Path(__file__).resolve().parents[1]
errors=[]
def check(c,m):
    if not c: errors.append(m)
def read(p): return (root/p).read_text(errors='ignore')

for p in ['src/Menu/FBGRMenuTheme.m','src/Menu/FBGRGateCategoryVC.m','src/Menu/FBGRGateRuntimeBrowserVC.m','src/Menu/FBGRBoolRuntimeBrowserVC.m','src/Runtime/FBGRBoolRuntimeInventory.m','src/Hooks/FBGRMCGateHooks.xm','src/Hooks/FBGRLiquidGlassHooks.xm']:
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
check('__attribute__((constructor))' in mc or '%ctor' in mc, 'MC hooks must have startup reapply path like WATweaks')
check('FBGRMCGateHooksInstallIfPersisted' in mc, 'MC startup path must be gated by persisted overrides')
check('FBGRMCGateHooksInstallKnownClasses' in mc and 'FBGRMCGateHooksInstallFullScan' in mc, 'MC hooks must split known startup from full scan')
check('dispatch_after' in mc, 'MC hooks must retry delayed after launch for late-loaded classes')
check('objc_getClassList' in mc and 'MSHookMessageEx' in mc, 'MC hooks must perform real runtime scan and hook')
check('getBool:withOptions:' in mc and 'getBool:withOptions:withDefault:' in mc, 'MC hooks must cover bool getter selectors')
ctor_match=re.search(r'FBGRMCGateHooksCtor\(void\).*?\n\}', mc, re.S)
ctor=ctor_match.group(0) if ctor_match else ''
check('FBGRMCGateHooksInstallFullScan' not in ctor and 'FBGRMCGateHooksEnsureInstalled' not in ctor, 'MC constructor must not call full broad scan directly')
check('mode=persisted startup known classes + on-demand full scan' in mc, 'MC diagnostic must describe safe startup/full scan split')

boolm=read('src/Runtime/FBGRBoolRuntimeInventory.m')
check('@implementation FBGRBoolRuntimeInventory' in boolm, 'BoolRuntime implementation context missing')
check('objc_getClassList' in boolm and 'class_getImageName' in boolm and 'class_copyMethodList' in boolm and 'method_copyReturnType' in boolm, 'Bool runtime must scan real ObjC runtime')
check('MSHookMessageEx' in boolm, 'Bool runtime must patch through MSHookMessageEx')
check('FBGRGateAllRuntimeHookSpecs' in boolm and 'FBGRGateRememberRuntimeHook' in boolm, 'Bool runtime must persist/reapply hook specs')
check('UIApplicationDidFinishLaunchingNotification' in boolm and 'startup=delayed' in boolm, 'Bool runtime restart reapply must be delayed, not dyld-immediate')

lg=read('src/Hooks/FBGRLiquidGlassHooks.xm')
check('UIApplicationDidFinishLaunchingNotification' in lg and 'startup=delayed' in lg, 'LiquidGlass restart reapply must be delayed')
check('FBGRLiquidGlassStartupPass' in lg and 'FBGRLGForced' in lg, 'LiquidGlass must only reapply persisted state when enabled')

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
print('OK: FBTweaks safe WATweaks-style startup validation passed')
