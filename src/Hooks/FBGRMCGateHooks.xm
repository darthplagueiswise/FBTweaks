// FBGRMCGateHooks.xm — safe MobileConfig BOOL overrides.
//
// Runtime contract:
//   - no constructor install
//   - no broad global ObjC class-list enumeration scan
//   - hot path reads only a C RAM cache
//   - slotId 0 is intentionally not overrideable because the runtime param carries
//     only the numeric slot and slot 0 is shared by many non-bool/string params.

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
static NSUInteger gHookedClassCount = 0;
static NSUInteger gHookedMethodCount = 0;

#define FBGR_MAX_OVERRIDES 4096
typedef struct { uint64_t slotId; BOOL value; } FBGROverride;
static FBGROverride gOverrideCache[FBGR_MAX_OVERRIDES];
static volatile int gOverrideCacheN = 0;

#define FBGR_MAX_HOOKS 256
typedef struct {
    Class hookClass;   // class for instance methods, metaclass for class methods
    SEL sel;
    IMP orig;
} FBGRMCHookRecord;
static FBGRMCHookRecord gHooks[FBGR_MAX_HOOKS];
static int gHookN = 0;

static BOOL FBGRCacheLookup(uint64_t slotId, BOOL *outValue) {
    if (slotId == 0) return NO;
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

static IMP FBGROrigFor(Class hookClass, SEL sel) {
    for (int i = 0; i < gHookN; i++) {
        if (gHooks[i].hookClass == hookClass && gHooks[i].sel == sel) return gHooks[i].orig;
    }
    return NULL;
}

static BOOL FBGRAlreadyHooked(Class hookClass, SEL sel) {
    for (int i = 0; i < gHookN; i++) {
        if (gHooks[i].hookClass == hookClass && gHooks[i].sel == sel) return YES;
    }
    return NO;
}

static void FBGRRecordHook(Class hookClass, SEL sel, IMP orig) {
    if (!hookClass || !sel || !orig || gHookN >= FBGR_MAX_HOOKS) return;
    gHooks[gHookN].hookClass = hookClass;
    gHooks[gHookN].sel = sel;
    gHooks[gHookN].orig = orig;
    gHookN++;
    gHookedMethodCount++;
}

typedef BOOL (*GetBool1IMP)(id, SEL, mc_bool_param_t);
typedef BOOL (*GetBoolDefaultIMP)(id, SEL, mc_bool_param_t, BOOL);
typedef BOOL (*GetBoolOptionsIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GetBoolOptionsDefaultIMP)(id, SEL, mc_bool_param_t, id, BOOL);
typedef void (*SetScrollIMP)(id, SEL, BOOL);

static BOOL h_getBool1(id self, SEL _cmd, mc_bool_param_t p) {
    if (gFBGRMCHookGuard) return NO;
    BOOL forced = NO;
    if (FBGRCacheLookup(p.value, &forced)) return forced;
    IMP orig = FBGROrigFor(object_getClass(self), _cmd);
    gFBGRMCHookGuard = YES;
    BOOL result = orig ? ((GetBool1IMP)orig)(self, _cmd, p) : NO;
    gFBGRMCHookGuard = NO;
    return result;
}

static BOOL h_getBoolDefault(id self, SEL _cmd, mc_bool_param_t p, BOOL def) {
    if (gFBGRMCHookGuard) return def;
    BOOL forced = NO;
    if (FBGRCacheLookup(p.value, &forced)) return forced;
    IMP orig = FBGROrigFor(object_getClass(self), _cmd);
    gFBGRMCHookGuard = YES;
    BOOL result = orig ? ((GetBoolDefaultIMP)orig)(self, _cmd, p, def) : def;
    gFBGRMCHookGuard = NO;
    return result;
}

static BOOL h_getBoolOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    if (gFBGRMCHookGuard) return NO;
    BOOL forced = NO;
    if (FBGRCacheLookup(p.value, &forced)) return forced;
    IMP orig = FBGROrigFor(object_getClass(self), _cmd);
    gFBGRMCHookGuard = YES;
    BOOL result = orig ? ((GetBoolOptionsIMP)orig)(self, _cmd, p, opts) : NO;
    gFBGRMCHookGuard = NO;
    return result;
}

static BOOL h_getBoolOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    if (gFBGRMCHookGuard) return def;
    BOOL forced = NO;
    if (FBGRCacheLookup(p.value, &forced)) return forced;
    IMP orig = FBGROrigFor(object_getClass(self), _cmd);
    gFBGRMCHookGuard = YES;
    BOOL result = orig ? ((GetBoolOptionsDefaultIMP)orig)(self, _cmd, p, opts, def) : def;
    gFBGRMCHookGuard = NO;
    return result;
}

static void h_setShouldEnableScrollableTabBar(id self, SEL _cmd, BOOL v) {
    IMP orig = FBGROrigFor(object_getClass(self), _cmd);
    BOOL forced = NO;
    if (FBGRCacheLookup(1217, &forced) && forced) v = YES;
    if (orig) ((SetScrollIMP)orig)(self, _cmd, v);
}

static BOOL FBGRSelectorNameContains(SEL sel, const char *needle) {
    const char *name = sel_getName(sel);
    return name && strstr(name, needle) != NULL;
}

static IMP FBGRReplacementForMethod(Method m, SEL sel) {
    if (!m) return NULL;
    unsigned int argc = method_getNumberOfArguments(m);
    if (sel_isEqual(sel, sel_registerName("setShouldEnableScrollableTabBar:"))) return (IMP)h_setShouldEnableScrollableTabBar;

    BOOL hasOptions = FBGRSelectorNameContains(sel, "Options") || FBGRSelectorNameContains(sel, "options");
    BOOL hasDefault = FBGRSelectorNameContains(sel, "Default") || FBGRSelectorNameContains(sel, "default");

    if (argc == 3) return (IMP)h_getBool1;
    if (argc == 4) return hasDefault ? (IMP)h_getBoolDefault : (hasOptions ? (IMP)h_getBoolOptions : (IMP)h_getBoolDefault);
    if (argc == 5) return (IMP)h_getBoolOptionsDefault;
    return NULL;
}

static void FBGRMCHookOne(Class owner, SEL sel, BOOL classMethod) {
    if (!owner || !sel || gHookN >= FBGR_MAX_HOOKS) return;

    Method m = classMethod ? class_getClassMethod(owner, sel) : class_getInstanceMethod(owner, sel);
    if (!m) return;

    Class hookClass = classMethod ? object_getClass(owner) : owner;
    if (!hookClass || FBGRAlreadyHooked(hookClass, sel)) return;

    IMP repl = FBGRReplacementForMethod(m, sel);
    if (!repl) return;

    IMP orig = NULL;
    MSHookMessageEx(hookClass, sel, repl, &orig);
    if (orig) FBGRRecordHook(hookClass, sel, orig);
}

static void FBGRMCHookClassByName(NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return;

    NSUInteger before = (NSUInteger)gHookN;
    SEL selectors[] = {
        sel_registerName("getBool:"),
        sel_registerName("getBool:withDefault:"),
        sel_registerName("getBool:default:"),
        sel_registerName("getBool:defaultValue:"),
        sel_registerName("getBool:withOptions:"),
        sel_registerName("getBool:withOptions:withDefault:"),
        sel_registerName("getBoolWithoutLogging:"),
        sel_registerName("getBoolWithoutLogging:withDefault:"),
        sel_registerName("getBoolWithoutExposure:"),
        sel_registerName("getBoolWithoutExposure:withDefault:"),
        sel_registerName("setShouldEnableScrollableTabBar:"),
    };
    const unsigned long count = sizeof(selectors) / sizeof(selectors[0]);
    for (unsigned long i = 0; i < count; i++) {
        FBGRMCHookOne(cls, selectors[i], NO);
        FBGRMCHookOne(cls, selectors[i], YES);
    }
    if ((NSUInteger)gHookN > before) gHookedClassCount++;
}

static void FBGRMCInstallHooksInternal(void) {
    if (gFBGRMCInstalled || gFBGRMCInstalling) { FBGRCacheRebuild(); return; }
    gFBGRMCInstalling = YES;

    // Static owners only. No global ObjC class-list enumeration and no arbitrary class_getInstanceMethod.
    NSArray<NSString *> *classes = @[
        @"FBMobileConfigContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigAdminIDContextManager",
        @"FBMobileConfigContextObjcImpl",
        @"FBMobileConfigGlobalContext",
        @"FBMobileConfigAPI",
        @"FBMobileConfigFBTAPI",
        @"FBMobileConfigFBTContextManager",
        @"RCTMobileConfigNative",
        @"MobileConfigModule",
    ];
    for (NSString *cn in classes) FBGRMCHookClassByName(cn);

    FBGRCacheRebuild();
    gFBGRMCInstalled = YES;
    gFBGRMCInstalling = NO;
    FBGRLogAppend([NSString stringWithFormat:@"MCGateHooks: installed classes=%lu methods=%lu cached=%d",
                   (unsigned long)gHookedClassCount, (unsigned long)gHookedMethodCount, gOverrideCacheN]);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ FBGRMCInstallHooksInternal(); });
}

extern "C" void FBGRMCGateHooksApplyPersistedOverrides(void) {
    FBGRCacheRebuild();
    if (gOverrideCacheN <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ FBGRMCInstallHooksInternal(); });
}

extern "C" void FBGRMCGateCacheRefresh(void) {
    if (gFBGRMCInstalled) FBGRCacheRebuild();
    else if (FBGRGateAllOverrideSlotIds().count > 0) FBGRMCGateHooksEnsureInstalled();
}

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\nhookedKnownClasses=%lu\nhookedMethods=%lu\ncachedOverrides=%d\nscan=disabled\nslot0Override=disabled",
        gFBGRMCInstalled ? @"YES" : @"NO",
        (unsigned long)gHookedClassCount,
        (unsigned long)gHookedMethodCount,
        gOverrideCacheN];
}
