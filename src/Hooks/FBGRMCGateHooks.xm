// FBGRMCGateHooks.xm — generic MobileConfig getBool: interceptor.
//
// Stability constraints:
//   - no constructor install
//   - no NSUserDefaults/NSString/logging from hook hot path
//   - original IMPs are stored in C arrays by Class, not NSDictionary NSString keys

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"

extern "C" void FBGRLogAppend(NSString *msg);

typedef BOOL (*GetBoolIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GetBoolWDIMP)(id, SEL, mc_bool_param_t, id, BOOL);
typedef void (*SetScrollIMP)(id, SEL, BOOL);

typedef struct {
    Class cls;
    GetBoolIMP origA;
    GetBoolWDIMP origB;
} FBGRMCHookEntry;

#define FBGR_MC_HOOK_MAX 64

static FBGRMCHookEntry gEntries[FBGR_MC_HOOK_MAX];
static uint32_t gEntryCount = 0;
static SetScrollIMP orig_setScrollable = NULL;
static NSUInteger gHooked = 0;
static BOOL gInstalled = NO;
static BOOL gInstalling = NO;
static dispatch_once_t gInitOnce;

static void FBGRMCInit(void) {
    dispatch_once(&gInitOnce, ^{
        gEntryCount = 0;
        gHooked = 0;
    });
}

static FBGRMCHookEntry *FBGREntryForClass(Class cls) {
    if (!cls) return NULL;
    uint32_t n = gEntryCount;
    for (uint32_t i = 0; i < n; i++) {
        if (gEntries[i].cls == cls) return &gEntries[i];
    }
    return NULL;
}

static FBGRMCHookEntry *FBGREntryEnsure(Class cls) {
    FBGRMCHookEntry *e = FBGREntryForClass(cls);
    if (e) return e;
    if (gEntryCount >= FBGR_MC_HOOK_MAX) return NULL;
    e = &gEntries[gEntryCount++];
    e->cls = cls;
    e->origA = NULL;
    e->origB = NULL;
    return e;
}

static inline BOOL FBGRShouldOverride(uint64_t slotId, BOOL *outValue) {
    if (FBGRGateIsSet(slotId)) {
        *outValue = FBGRGateGet(slotId);
        return YES;
    }
    return NO;
}

static BOOL h_getBoolWithOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    BOOL forced = NO;
    if (FBGRShouldOverride(p.value, &forced)) return forced;

    FBGRMCHookEntry *e = FBGREntryForClass(object_getClass(self));
    GetBoolIMP orig = e ? e->origA : NULL;
    return orig ? orig(self, _cmd, p, opts) : NO;
}

static BOOL h_getBoolWithOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    BOOL forced = NO;
    if (FBGRShouldOverride(p.value, &forced)) return forced;

    FBGRMCHookEntry *e = FBGREntryForClass(object_getClass(self));
    GetBoolWDIMP orig = e ? e->origB : NULL;
    return orig ? orig(self, _cmd, p, opts, def) : def;
}

static void h_setShouldEnableScrollableTabBar(id self, SEL _cmd, BOOL v) {
    BOOL forced = NO;
    if (FBGRShouldOverride(1217, &forced) && forced) v = YES;
    if (orig_setScrollable) orig_setScrollable(self, _cmd, v);
}

static void FBGRMCHookClass(Class cls) {
    if (!cls) return;
    FBGRMCHookEntry *e = FBGREntryEnsure(cls);
    if (!e) return;

    SEL sA = sel_registerName("getBool:withOptions:");
    SEL sB = sel_registerName("getBool:withOptions:withDefault:");
    SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");

    if (!e->origA && class_getInstanceMethod(cls, sA)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sA, (IMP)h_getBoolWithOptions, &orig);
        if (orig) {
            e->origA = (GetBoolIMP)orig;
            gHooked++;
        }
    }

    if (!e->origB && class_getInstanceMethod(cls, sB)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sB, (IMP)h_getBoolWithOptionsDefault, &orig);
        if (orig) e->origB = (GetBoolWDIMP)orig;
    }

    if (!orig_setScrollable && class_getInstanceMethod(cls, sC)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sC, (IMP)h_setShouldEnableScrollableTabBar, &orig);
        if (orig) orig_setScrollable = (SetScrollIMP)orig;
    }
}

static void FBGRMCInstall(void) {
    if (gInstalled || gInstalling) return;
    gInstalling = YES;

    FBGRMCInit();
    FBGRGateStoreWarmup();

    for (NSString *cn in @[
        @"FBMobileConfigContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigFBTAPI",
        @"FBMobileConfigFBTContextManager",
        @"FBMobileConfigAPI",
        @"FBMobileConfigGlobalContext",
    ]) {
        Class cls = NSClassFromString(cn);
        if (cls) FBGRMCHookClass(cls);
    }

    // No global class-list fallback here. It is too heavy for Facebook preload.
    gInstalled = YES;
    gInstalling = NO;

    FBGRLogAppend([NSString stringWithFormat:@"MCGateHooks installed on %lu classes", (unsigned long)gHooked]);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) { FBGRMCInstall(); }

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    FBGRMCInit();
    NSMutableArray *classes = [NSMutableArray array];
    uint32_t n = gEntryCount;
    for (uint32_t i = 0; i < n; i++) {
        if (gEntries[i].cls) [classes addObject:NSStringFromClass(gEntries[i].cls)];
    }
    return [NSString stringWithFormat:
        @"installed=%@\nhookedClasses=%lu\nscrollable=%@\noverrides=%lu\nclasses=[%@]",
        gInstalled ? @"YES" : @"NO",
        (unsigned long)gHooked,
        orig_setScrollable ? @"YES" : @"NO",
        (unsigned long)FBGRGateAllOverrideSlotIds().count,
        [classes componentsJoinedByString:@","]];
}
