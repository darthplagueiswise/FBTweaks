// FBGRMCGateHooks.xm — MobileConfig bool override hooks.
//
// CRASH-SAFE DESIGN (do not weaken — these prevented the depth-2053/1954 loops):
//   1. __thread reentrancy guard set IMMEDIATELY on entry, before orig().
//   2. Pure-C bypass when guard active: object_getClass + C array, no CF/ObjC.
//   3. C-level override cache (no NSUserDefaults reads in hot path).
//   4. Delayed install (2s) so CF/TSD/MC are initialized before we hook.
//
// COVERAGE: all bool getters take mc_bool_param_t == {Q} (a uint64 slotId),
// confirmed ABI-identical across mc_bool/sessionbased/sessionless/adminID.
// We hook every variant that wraps the slot in the first arg:
//   getBool:withOptions:            (slot, opts)
//   getBool:withOptions:withDefault:(slot, opts, def)
//   getBool:                        (slot)
//   getBool:default:                (slot, def)
//   getBoolWithoutLogging:          (slot)
//   getBoolWithoutLogging:withDefault:(slot, def)
// plus the tab-bar setter setShouldEnableScrollableTabBar:.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"

static __thread BOOL gFBGRMCHookGuard = NO;

// ── Per-class original IMP table (pure C, pointer-compared) ───────────────────
#define FBGR_MAX_HOOKED_CLS 16
typedef struct {
    Class cls;
    IMP   getBoolOpt;      // getBool:withOptions:
    IMP   getBoolOptDef;   // getBool:withOptions:withDefault:
    IMP   getBoolPlain;    // getBool:
    IMP   getBoolDef;      // getBool:default:
    IMP   getBoolNoLog;    // getBoolWithoutLogging:
    IMP   getBoolNoLogDef; // getBoolWithoutLogging:withDefault:
} FBGRHookedClass;

static FBGRHookedClass gHooked[FBGR_MAX_HOOKED_CLS];
static int             gHookedN = 0;

static FBGRHookedClass *FBGRSlotFor(Class cls) {
    for (int i = 0; i < gHookedN; i++)
        if (gHooked[i].cls == cls) return &gHooked[i];
    return NULL;
}

// ── C override cache ──────────────────────────────────────────────────────────
#define FBGR_MAX_OVERRIDES 128
typedef struct { uint64_t slotId; BOOL value; } FBGROverride;
static FBGROverride gOverrideCache[FBGR_MAX_OVERRIDES];
static int          gOverrideCacheN = 0;
static BOOL         gHaveSlotZero = NO;   // slot 0 is valid; track explicitly
static BOOL         gSlotZeroValue = NO;

static BOOL FBGRCacheLookup(uint64_t slotId, BOOL *outValue) {
    if (slotId == 0) {
        if (gHaveSlotZero) { *outValue = gSlotZeroValue; return YES; }
        return NO;
    }
    for (int i = 0; i < gOverrideCacheN; i++)
        if (gOverrideCache[i].slotId == slotId) { *outValue = gOverrideCache[i].value; return YES; }
    return NO;
}

static void FBGRCacheRebuild(void) {
    @autoreleasepool {
        gOverrideCacheN = 0; gHaveSlotZero = NO; gSlotZeroValue = NO;
        for (NSNumber *n in FBGRGateAllOverrideSlotIds()) {
            uint64_t s = [n unsignedLongLongValue];
            if (s == 0) { gHaveSlotZero = YES; gSlotZeroValue = FBGRGateGet(0); continue; }
            if (gOverrideCacheN >= FBGR_MAX_OVERRIDES) break;
            gOverrideCache[gOverrideCacheN].slotId = s;
            gOverrideCache[gOverrideCacheN].value  = FBGRGateGet(s);
            gOverrideCacheN++;
        }
        FBGRLogAppend([NSString stringWithFormat:@"MCGateHooks: cache %d overrides%@",
                       gOverrideCacheN, gHaveSlotZero ? @" (+slot0)" : @""]);
    }
}

// ── Trampolines ───────────────────────────────────────────────────────────────
typedef BOOL (*GBOpt)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GBOptDef)(id, SEL, mc_bool_param_t, id, BOOL);
typedef BOOL (*GBPlain)(id, SEL, mc_bool_param_t);
typedef BOOL (*GBDef)(id, SEL, mc_bool_param_t, BOOL);
typedef void (*SetScrollIMP)(id, SEL, BOOL);
static SetScrollIMP orig_setScrollable = NULL;

// Macro pattern keeps every trampoline identical & crash-safe.
#define FBGR_GUARD_BYPASS(origExpr, callExpr) \
    if (gFBGRMCHookGuard) { IMP _o = (origExpr); return _o ? (callExpr) : NO; }

static BOOL h_getBoolOpt(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    FBGRHookedClass *s = FBGRSlotFor(object_getClass(self));
    IMP orig = s ? s->getBoolOpt : NULL;
    if (gFBGRMCHookGuard) return orig ? ((GBOpt)orig)(self,_cmd,p,opts) : NO;
    gFBGRMCHookGuard = YES;
    BOOL forced = NO, result;
    if (FBGRCacheLookup(p.value, &forced)) result = forced;
    else result = orig ? ((GBOpt)orig)(self,_cmd,p,opts) : NO;
    gFBGRMCHookGuard = NO;
    return result;
}
static BOOL h_getBoolOptDef(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    FBGRHookedClass *s = FBGRSlotFor(object_getClass(self));
    IMP orig = s ? s->getBoolOptDef : NULL;
    if (gFBGRMCHookGuard) return orig ? ((GBOptDef)orig)(self,_cmd,p,opts,def) : def;
    gFBGRMCHookGuard = YES;
    BOOL forced = NO, result;
    if (FBGRCacheLookup(p.value, &forced)) result = forced;
    else result = orig ? ((GBOptDef)orig)(self,_cmd,p,opts,def) : def;
    gFBGRMCHookGuard = NO;
    return result;
}
static BOOL h_getBoolPlain(id self, SEL _cmd, mc_bool_param_t p) {
    FBGRHookedClass *s = FBGRSlotFor(object_getClass(self));
    IMP orig = s ? s->getBoolPlain : NULL;
    if (gFBGRMCHookGuard) return orig ? ((GBPlain)orig)(self,_cmd,p) : NO;
    gFBGRMCHookGuard = YES;
    BOOL forced = NO, result;
    if (FBGRCacheLookup(p.value, &forced)) result = forced;
    else result = orig ? ((GBPlain)orig)(self,_cmd,p) : NO;
    gFBGRMCHookGuard = NO;
    return result;
}
static BOOL h_getBoolDef(id self, SEL _cmd, mc_bool_param_t p, BOOL def) {
    FBGRHookedClass *s = FBGRSlotFor(object_getClass(self));
    IMP orig = s ? s->getBoolDef : NULL;
    if (gFBGRMCHookGuard) return orig ? ((GBDef)orig)(self,_cmd,p,def) : def;
    gFBGRMCHookGuard = YES;
    BOOL forced = NO, result;
    if (FBGRCacheLookup(p.value, &forced)) result = forced;
    else result = orig ? ((GBDef)orig)(self,_cmd,p,def) : def;
    gFBGRMCHookGuard = NO;
    return result;
}
static BOOL h_getBoolNoLog(id self, SEL _cmd, mc_bool_param_t p) {
    FBGRHookedClass *s = FBGRSlotFor(object_getClass(self));
    IMP orig = s ? s->getBoolNoLog : NULL;
    if (gFBGRMCHookGuard) return orig ? ((GBPlain)orig)(self,_cmd,p) : NO;
    gFBGRMCHookGuard = YES;
    BOOL forced = NO, result;
    if (FBGRCacheLookup(p.value, &forced)) result = forced;
    else result = orig ? ((GBPlain)orig)(self,_cmd,p) : NO;
    gFBGRMCHookGuard = NO;
    return result;
}
static BOOL h_getBoolNoLogDef(id self, SEL _cmd, mc_bool_param_t p, BOOL def) {
    FBGRHookedClass *s = FBGRSlotFor(object_getClass(self));
    IMP orig = s ? s->getBoolNoLogDef : NULL;
    if (gFBGRMCHookGuard) return orig ? ((GBDef)orig)(self,_cmd,p,def) : def;
    gFBGRMCHookGuard = YES;
    BOOL forced = NO, result;
    if (FBGRCacheLookup(p.value, &forced)) result = forced;
    else result = orig ? ((GBDef)orig)(self,_cmd,p,def) : def;
    gFBGRMCHookGuard = NO;
    return result;
}
static void h_setScrollable(id self, SEL _cmd, BOOL v) {
    BOOL forced = NO;
    if (!gFBGRMCHookGuard && FBGRCacheLookup(1217, &forced) && forced) v = YES;
    if (orig_setScrollable) orig_setScrollable(self, _cmd, v);
}

// ── Installation ──────────────────────────────────────────────────────────────
static NSUInteger gSelectorsHooked = 0;

static void FBGRHookOne(Class cls, const char *selName, IMP repl, IMP *store) {
    SEL sel = sel_registerName(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    IMP orig = NULL;
    MSHookMessageEx(cls, sel, repl, &orig);
    if (orig) { *store = orig; gSelectorsHooked++; }
}

static void FBGRMCHookClass(Class cls) {
    if (!cls || gHookedN >= FBGR_MAX_HOOKED_CLS || FBGRSlotFor(cls)) return;
    FBGRHookedClass *s = &gHooked[gHookedN];
    s->cls = cls;
    FBGRHookOne(cls, "getBool:withOptions:",             (IMP)h_getBoolOpt,     &s->getBoolOpt);
    FBGRHookOne(cls, "getBool:withOptions:withDefault:", (IMP)h_getBoolOptDef,  &s->getBoolOptDef);
    FBGRHookOne(cls, "getBool:",                         (IMP)h_getBoolPlain,   &s->getBoolPlain);
    FBGRHookOne(cls, "getBool:default:",                 (IMP)h_getBoolDef,     &s->getBoolDef);
    FBGRHookOne(cls, "getBoolWithoutLogging:",           (IMP)h_getBoolNoLog,   &s->getBoolNoLog);
    FBGRHookOne(cls, "getBoolWithoutLogging:withDefault:",(IMP)h_getBoolNoLogDef,&s->getBoolNoLogDef);
    BOOL any = s->getBoolOpt||s->getBoolOptDef||s->getBoolPlain||s->getBoolDef||s->getBoolNoLog||s->getBoolNoLogDef;
    if (any) gHookedN++;
}

static void FBGRMCInstallHooks(void) {
    for (NSString *cn in @[
        @"FBMobileConfigContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigAdminIDContextManager",
        @"FBMobileConfigFBTAPI",
        @"FBMobileConfigFBTContextManager",
        @"FBMobileConfigAPI",
        @"FBMobileConfigGlobalContext",
    ]) {
        Class cls = NSClassFromString(cn);
        if (cls) FBGRMCHookClass(cls);
    }
    if (!orig_setScrollable) {
        SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");
        unsigned int n = 0; Class *all = objc_copyClassList(&n);
        for (unsigned i = 0; i < n && !orig_setScrollable; i++) {
            if (class_getInstanceMethod(all[i], sC)) {
                IMP orig = NULL;
                MSHookMessageEx(all[i], sC, (IMP)h_setScrollable, &orig);
                if (orig) orig_setScrollable = (SetScrollIMP)orig;
            }
        }
        free(all);
    }
    FBGRCacheRebuild();
    FBGRLogAppend([NSString stringWithFormat:
        @"MCGateHooks: %lu classes, %lu selectors, scrollable=%@",
        (unsigned long)gHookedN, (unsigned long)gSelectorsHooked,
        orig_setScrollable ? @"Y" : @"N"]);
}

// ── Public API ────────────────────────────────────────────────────────────────
extern "C" void FBGRMCGateHooksEnsureInstalled(void) { /* delayed in ctor */ }
extern "C" void FBGRMCGateCacheRefresh(void) { FBGRCacheRebuild(); }
extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:
        @"classes=%lu selectors=%lu scrollable=%@ overrides=%d%@",
        (unsigned long)gHookedN, (unsigned long)gSelectorsHooked,
        orig_setScrollable ? @"YES" : @"NO",
        gOverrideCacheN, gHaveSlotZero ? @" (+slot0)" : @""];
}

__attribute__((constructor))
static void FBGRMCGateHooksCtor(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ FBGRMCInstallHooks(); });
}
