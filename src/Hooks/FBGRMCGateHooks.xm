// FBGRMCGateHooks.xm — safe MobileConfig BOOL overrides.
//
// Built from the non-crashing a2e50 base. This file intentionally avoids:
//   - constructor install
//   - broad runtime class scans
//   - NSString/NSUserDefaults/logging in getBool hot path
// Hooks are installed only when the user toggles an override or asks for diag.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"

static __thread BOOL gFBGRMCHookGuard = NO;
static BOOL gFBGRMCInstalled = NO;
static BOOL gFBGRMCInstalling = NO;
static NSUInteger gHookedCount = 0;

#define FBGR_MAX_HOOKED_CLS 64
typedef struct {
    Class cls;
    IMP getBoolOrig;
    IMP getBoolWDOrig;
    IMP scrollOrig;
} FBGRHookedClass;
static FBGRHookedClass gHookedClasses[FBGR_MAX_HOOKED_CLS];
static int gHookedN = 0;

#define FBGR_MAX_OVERRIDES 2048
typedef struct { uint64_t slotId; BOOL value; } FBGROverride;
static FBGROverride gOverrideCache[FBGR_MAX_OVERRIDES];
static volatile int gOverrideCacheN = 0;

static IMP FBGRGetOrig(Class cls, int kind) {
    for (int i = 0; i < gHookedN; i++) {
        if (gHookedClasses[i].cls == cls) {
            if (kind == 0) return gHookedClasses[i].getBoolOrig;
            if (kind == 1) return gHookedClasses[i].getBoolWDOrig;
            return gHookedClasses[i].scrollOrig;
        }
    }
    return NULL;
}

static BOOL FBGRClassAlreadyHooked(Class cls) {
    for (int i = 0; i < gHookedN; i++) if (gHookedClasses[i].cls == cls) return YES;
    return NO;
}

static BOOL FBGRCacheLookup(uint64_t slotId, BOOL *outValue) {
    int n = gOverrideCacheN;
    for (int i = 0; i < n; i++) {
        if (gOverrideCache[i].slotId == slotId) {
            *outValue = gOverrideCache[i].value;
            return YES;
        }
    }
    return NO;
}

static void FBGRCacheRebuild(void) {
    @autoreleasepool {
        FBGRGateStoreWarmup();
        gOverrideCacheN = 0;
        NSArray<NSNumber *> *ids = FBGRGateAllOverrideSlotIds();
        for (NSNumber *n in ids) {
            if (gOverrideCacheN >= FBGR_MAX_OVERRIDES) break;
            uint64_t slot = [n unsignedLongLongValue];
            if (slot == 0) continue;
            gOverrideCache[gOverrideCacheN].slotId = slot;
            gOverrideCache[gOverrideCacheN].value = FBGRGateGet(slot);
            gOverrideCacheN++;
        }
    }
}

typedef BOOL (*GetBoolIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GetBoolWDIMP)(id, SEL, mc_bool_param_t, id, BOOL);
typedef void (*SetScrollIMP)(id, SEL, BOOL);

static BOOL h_getBoolWithOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    // Critical recursion guard:
    // Some FBSharedFramework MC resolvers call back into another getBool while the
    // original IMP is still resolving the current param. If we call orig again
    // while guarded, the original re-enters the hooked selector forever:
    //   FBTweaks -> FBSharedFramework -> FBTweaks -> ... -> stack guard crash.
    // Therefore guarded re-entry must return a neutral fallback immediately.
    if (gFBGRMCHookGuard) return NO;

    BOOL forced = NO;
    if (FBGRCacheLookup(p.value, &forced)) return forced;

    IMP orig = FBGRGetOrig(object_getClass(self), 0);
    gFBGRMCHookGuard = YES;
    BOOL result = orig ? ((GetBoolIMP)orig)(self, _cmd, p, opts) : NO;
    gFBGRMCHookGuard = NO;
    return result;
}

static BOOL h_getBoolWithOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    // Same recursion rule as getBool:withOptions:. When this path has a default,
    // the safest guarded fallback is the callsite default.
    if (gFBGRMCHookGuard) return def;

    BOOL forced = NO;
    if (FBGRCacheLookup(p.value, &forced)) return forced;

    IMP orig = FBGRGetOrig(object_getClass(self), 1);
    gFBGRMCHookGuard = YES;
    BOOL result = orig ? ((GetBoolWDIMP)orig)(self, _cmd, p, opts, def) : def;
    gFBGRMCHookGuard = NO;
    return result;
}

static void h_setShouldEnableScrollableTabBar(id self, SEL _cmd, BOOL v) {
    IMP orig = FBGRGetOrig(object_getClass(self), 2);
    BOOL forced = NO;
    if (FBGRCacheLookup(1217, &forced) && forced) v = YES;
    if (orig) ((SetScrollIMP)orig)(self, _cmd, v);
}

static void FBGRMCHookClass(Class cls) {
    if (!cls || gHookedN >= FBGR_MAX_HOOKED_CLS || FBGRClassAlreadyHooked(cls)) return;

    SEL sA = sel_registerName("getBool:withOptions:");
    SEL sB = sel_registerName("getBool:withOptions:withDefault:");
    SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");

    Method mA = class_getInstanceMethod(cls, sA);
    Method mB = class_getInstanceMethod(cls, sB);
    Method mC = class_getInstanceMethod(cls, sC);
    if (!mA && !mB && !mC) return;

    FBGRHookedClass *slot = &gHookedClasses[gHookedN];
    memset(slot, 0, sizeof(*slot));
    slot->cls = cls;
    BOOL hookedAny = NO;

    if (mA) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sA, (IMP)h_getBoolWithOptions, &orig);
        if (orig) { slot->getBoolOrig = orig; hookedAny = YES; }
    }
    if (mB) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sB, (IMP)h_getBoolWithOptionsDefault, &orig);
        if (orig) { slot->getBoolWDOrig = orig; hookedAny = YES; }
    }
    if (mC) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sC, (IMP)h_setShouldEnableScrollableTabBar, &orig);
        if (orig) { slot->scrollOrig = orig; hookedAny = YES; }
    }

    if (hookedAny) { gHookedN++; gHookedCount++; }
}

static void FBGRMCInstallHooksInternal(void) {
    if (gFBGRMCInstalled || gFBGRMCInstalling) { FBGRCacheRebuild(); return; }
    gFBGRMCInstalling = YES;

    // Static owners only. No global class scan: class_getInstanceMethod on arbitrary
    // Facebook classes triggered method resolution and crashed in prior builds.
    NSArray<NSString *> *classes = @[
        @"FBMobileConfigContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigFBTAPI",
        @"FBMobileConfigFBTContextManager",
        @"FBMobileConfigAPI",
        @"FBMobileConfigGlobalContext",
        @"FBMobileConfigContextObjcImpl",
        @"FBMobileConfigAdminIDContextManager",
        @"RCTMobileConfigNative",
    ];
    for (NSString *cn in classes) FBGRMCHookClass(NSClassFromString(cn));

    FBGRCacheRebuild();
    gFBGRMCInstalled = YES;
    gFBGRMCInstalling = NO;
    FBGRLogAppend([NSString stringWithFormat:@"MCGateHooks: installed on %lu known classes, cached=%d", (unsigned long)gHookedCount, gOverrideCacheN]);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) {
    // Do not install synchronously from UISwitch valueChanged. Let UIKit finish
    // the toggle/menu update first, then hook MC on the next runloop slice.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ FBGRMCInstallHooksInternal(); });
}

extern "C" void FBGRMCGateCacheRefresh(void) {
    if (gFBGRMCInstalled) FBGRCacheRebuild();
    else if (FBGRGateAllOverrideSlotIds().count > 0) FBGRMCGateHooksEnsureInstalled();
}

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\nhookedKnownClasses=%lu\ncachedOverrides=%d\nscan=disabled",
        gFBGRMCInstalled ? @"YES" : @"NO",
        (unsigned long)gHookedCount,
        gOverrideCacheN];
}
