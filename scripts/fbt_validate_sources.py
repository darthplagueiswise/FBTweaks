#!/usr/bin/env python3
from pathlib import Path
import gzip, json, sys, re

root = Path(__file__).resolve().parents[1]
errors = []

def check(cond, msg):
    if not cond:
        errors.append(msg)

mf = (root / 'Makefile').read_text(errors='ignore')
check('TARGET := iphone:clang:26.0:16.3' in mf, 'Makefile target must use iOS26 SDK baseline')
check('iPhoneOS26.0.sdk' in mf, 'Makefile must reference iPhoneOS26.0.sdk')
check('modules/fishhook/fishhook.c' in mf, 'Makefile must build vendored fishhook.c')
check('resources/runtime/*.json.gz' in mf, 'Makefile must stage gz runtime JSON metadata')
check('INSTALL_TARGET_PROCESSES = Facebook' in mf, 'Makefile must target Facebook process')
check('-include src/FBGramPrefix.h' not in mf, 'Makefile must not force-include ObjC prefix into fishhook.c')
check('-fuse-ld=lld' not in mf, 'Makefile must not force lld on macOS/Theos SDK26 workflow')
check('-fuse-ld=lld' not in mf, 'Makefile must not pass -fuse-ld=lld on GitHub macOS clang for iOS')

plist = (root / 'FBTweaks.plist').read_text(errors='ignore')
check('com.facebook.Facebook' in plist, 'FBTweaks.plist must filter com.facebook.Facebook')

for f in ['modules/fishhook/fishhook.c','modules/fishhook/fishhook.h','build.sh','build-fast.sh','.github/workflows/buildtweak.yml','scripts/validate-sdk26-fbtweaks.sh']:
    check((root / f).exists(), f'{f} missing')

for p in root.glob('src/**/*.m'):
    txt = p.read_text(errors='ignore')
    check('extern "C"' not in txt, f'{p.relative_to(root)} contains extern "C" but is compiled as .m')
    check('@property(nonatomic, strong) dispatch_once_t' not in txt, f'{p.relative_to(root)} has invalid strong dispatch_once_t property')

for p in ['src/Hooks/FBGRLiquidGlassHooks.xm','src/Hooks/FBGRMCGateHooks.xm','src/Hooks/FBGRDogFoodHooks.xm']:
    check((root / p).exists(), f'{p} missing')

tw = (root / 'src/Tweak.x').read_text(errors='ignore')
check('FBGRLiquidGlassEnsureInstalled' in tw, 'Tweak.x does not initialize LiquidGlass hook')
check('FBGRMCGateHooksApplyPersistedOverrides' in tw, 'Tweak.x must warm persisted overrides on launch')
check('FBGRMCGateHooksEnsureInstalled();' not in tw, 'Tweak.x must not directly install MC gate hooks during launch')
check('%hook FDSTouchStateAnnouncingControl' in tw, 'Tweak.x must preserve exact working tab-button longpress hook')
check('FBGRIsExactTabButtonCandidate' in tw and 'FBGRSizeLooksLikeTabButton' in tw, 'Tweak.x must preserve exact tab button filtering')
check('numberOfTapsRequired = 3' in tw, 'Tweak.x must preserve one-finger triple tap fallback on exact button')
check('numberOfTouchesRequired = 2' not in tw and 'numberOfTouchesRequired = 3' not in tw, 'Tweak.x must not use global 2/3-finger gesture')

mc = (root / 'src/Hooks/FBGRMCGateHooks.xm').read_text(errors='ignore')
check('__attribute__((constructor))' not in mc, 'FBGRMCGateHooks.xm must not install from constructor')
check('objc_copyClassList' not in mc, 'FBGRMCGateHooks.xm must not do global class scan')
check('FBGRLogAppend(msg)' not in mc, 'FBGRMCGateHooks.xm must not log inside getBool hot path')
check('NSStringFromClass([self class])' not in mc, 'FBGRMCGateHooks.xm must not allocate NSString in hook hot path')
check('FBMobileConfigContextManager' in mc and 'FBMobileConfigUserSessionContextManager' in mc and 'FBMobileConfigSessionlessContextManager' in mc, 'MC hooks must include validated MobileConfig owner classes')
check('RCTMobileConfigNative' in mc, 'MC hooks must include RN MobileConfig surface')
check('if (gFBGRMCHookGuard) return def;' in mc, 'FBGRMCGateHooks default path must return def during guarded re-entry')
check('FBGRMCGateHooksApplyPersistedOverrides' in mc, 'FBGRMCGateHooks must export persisted apply API')

obs = (root / 'src/Hooks/FBGRMCPropsObserver.xm').read_text(errors='ignore')
check('__attribute__((constructor))' not in obs, 'FBGRMCPropsObserver.xm must not install from constructor')
if 'static BOOL obsTrampoline' in obs:
    section = obs.split('static BOOL obsTrampoline',1)[1].split('return r;',1)[0]
    check('FBGRPref(kFBGRMCObserverEnabled)' not in section, 'observer trampoline must use cached enabled flag')

store = (root / 'src/Runtime/FBGRGateStore.m').read_text(errors='ignore')
hot_is_set = store.split('BOOL FBGRGateIsSet')[1].split('BOOL FBGRGateGet')[0]
hot_get = store.split('BOOL FBGRGateGet')[1].split('void FBGRGateSet')[0]
check('FBGRPrefs' not in hot_is_set and 'NSString' not in hot_is_set, 'FBGRGateIsSet hot path must not use NSUserDefaults/NSString')
check('FBGRPrefs' not in hot_get and 'NSString' not in hot_get, 'FBGRGateGet hot path must not use NSUserDefaults/NSString')
check('if (slotId == 0) return' not in store, 'GateStore must not drop legitimate bool slotId 0')
check('slotId > 0' not in store, 'GateStoreAllOverrideSlotIds must include legitimate slotId 0')

lg = (root / 'src/Hooks/FBGRLiquidGlassHooks.xm').read_text(errors='ignore')
check('IGLiquidGlassExperimentHelper' in lg, 'LiquidGlass hook must target SDK26 IGLiquidGlassExperimentHelper classes')
check('MSHookMessageEx' in lg, 'LiquidGlass SDK26 path must use MSHookMessageEx')
check('METAIsLiquidGlassEnabled' in lg, 'LiquidGlass must keep fishhook fallback')
check('__attribute__((constructor))' not in lg, 'LiquidGlass must not install from constructor; Tweak.x owns startup')

cat = (root / 'src/Runtime/FBGRMCCatalog.m').read_text(errors='ignore')
check('FBGRCollectMetadataFiles' in cat, 'MCCatalog must scan app/container directories for live metadata files')
check('Library/Application Support/FBTweaks' in cat and 'Documents/FBTweaks' in cat, 'MCCatalog must load from app data-container paths')
check('NSBundle.mainBundle.bundlePath' in cat and 'Facebook.app/ReactMobileConfigMetadata.json' in cat, 'MCCatalog must prefer the live ReactMobileConfigMetadata.json inside Facebook.app')
check('p.slotId > 0 && [p.type isEqualToString:@"boolValue"]' not in cat, 'MCCatalog must index bool slotId 0')

rt = (root / 'src/Menu/FBGRGateRuntimeBrowserVC.m').read_text(errors='ignore')
check('&& p.slotId > 0' not in rt.split('- (BOOL)canOverrideParam')[1].split('}')[0], 'Runtime Browser must allow bool slotId 0')

reg = (root / 'src/Runtime/FBGRGateRegistry.m').read_text(errors='ignore')
for slot, name in [(876,'fb_ford:is_employee'),(4623,'xplat_lwi:is_employee'),(1264,'gaming_tab_rn'),(2142,'mp_ai_assistant_bot'),(3953,'should_show_explore_tab')]:
    check(str(slot) in reg and name in reg, f'GateRegistry missing metadata(7) slot {slot} {name}')
check('874,' not in reg and '4620,' not in reg and '1247,' not in reg, 'GateRegistry still contains stale metadata slots')
check('0xDDF0' not in reg, 'GateRegistry must not expose fake DogFood slot')

surf = (root / 'src/Menu/FBGRSurfaceListVC.m').read_text(errors='ignore')
check('FBGRRootSectionDogFood' in surf and 'Apply Employee/Internal/DLP agora' in surf, 'SurfaceList must expose real DogFood/Internal action section')

meta = root / 'resources/runtime/ReactMobileConfigMetadata.json.gz'
check(meta.exists(), 'ReactMobileConfigMetadata.json.gz missing')
if meta.exists():
    try:
        with gzip.open(meta, 'rt', encoding='utf-8') as f:
            j = json.load(f)
        schema = j.get('schema', {})
        bool_count = sum(1 for v in schema.values() if isinstance(v, dict) and v.get('type') == 'boolValue')
        check(len(schema) == 5377, f'ReactMobileConfigMetadata schema must be 5377 for current build, got {len(schema)}')
        check(bool_count == 4679, f'ReactMobileConfigMetadata bool count must be 4679, got {bool_count}')
        print(f'ReactMobileConfigMetadata.json.gz: OK, {len(schema)} entries, {bool_count} bool params')
    except Exception as e:
        errors.append(f'ReactMobileConfigMetadata.json.gz invalid: {e}')

if errors:
    print('FBTweaks validation failed:', file=sys.stderr)
    for e in errors:
        print(' - ' + e, file=sys.stderr)
    sys.exit(1)
print('OK: FBTweaks SDK26 runtime base validation passed')
