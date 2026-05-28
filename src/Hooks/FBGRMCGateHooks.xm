// FBGRMCGateHooks.xm — generic MobileConfig getBool: interceptor.
// Checks FBGRGateStore for each slotId. If a store override exists → return it.
// Hooks all four mc_bool param variants (same ABI, same trampoline).
// Also hooks setShouldEnableScrollableTabBar:.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"

// ── Special: slotId 0 = _METAIsLiquidGlassEnabled (C gate, handled by fishhook)
// For slotId 0 we check the master pref directly.
static inline BOOL FBGRShouldOverride(uint64_t slotId, BOOL *outValue) {
    // slotId 0: LiquidGlass C gate master toggle
    if (slotId == 0 && FBGRPref(kFBGRLiquidGlassMaster)) { *outValue = YES; return YES; }
    if (FBGRGateIsSet(slotId)) { *outValue = FBGRGateGet(slotId); return YES; }
    return NO;
}

typedef BOOL (*GetBoolIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GetBoolWDIMP)(id, SEL, mc_bool_param_t, id, BOOL);
typedef void (*SetScrollIMP)(id, SEL, BOOL);

static NSMutableDictionary<NSString*,NSValue*> *gOrigBool   = nil;
static NSMutableDictionary<NSString*,NSValue*> *gOrigBoolWD = nil;
static SetScrollIMP orig_setScrollable = NULL;
static NSUInteger gHooked = 0;
static dispatch_once_t gOnce;

static void FBGRMCInit(void) {
    dispatch_once(&gOnce, ^{
        gOrigBool   = [NSMutableDictionary dictionaryWithCapacity:8];
        gOrigBoolWD = [NSMutableDictionary dictionaryWithCapacity:8];
    });
}

static BOOL h_getBoolWithOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    BOOL forced;
    if (FBGRShouldOverride(p.value, &forced)) {
        NSString *msg = [NSString stringWithFormat:@"MC getBool slotId=%llu → %@ (override)",
                         (unsigned long long)p.value, forced ? @"YES" : @"NO"];
        FBGRLogAppend(msg);
        return forced;
    }
    NSString *cls = NSStringFromClass([self class]);
    GetBoolIMP orig = gOrigBool[cls] ? (GetBoolIMP)[gOrigBool[cls] pointerValue] : NULL;
    return orig ? orig(self, _cmd, p, opts) : NO;
}

static BOOL h_getBoolWithOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    BOOL forced;
    if (FBGRShouldOverride(p.value, &forced)) return forced;
    NSString *cls = NSStringFromClass([self class]);
    GetBoolWDIMP orig = gOrigBoolWD[cls] ? (GetBoolWDIMP)[gOrigBoolWD[cls] pointerValue] : NULL;
    return orig ? orig(self, _cmd, p, opts, def) : def;
}

static void h_setShouldEnableScrollableTabBar(id self, SEL _cmd, BOOL v) {
    BOOL forced;
    // Check if slotId 1217 (scroll_behind_ftb) is set — that implies scrollable tab bar
    if (FBGRShouldOverride(1217, &forced) && forced) v = YES;
    if (orig_setScrollable) orig_setScrollable(self, _cmd, v);
}

static void FBGRMCHookClass(Class cls) {
    NSString *cn = NSStringFromClass(cls);
    SEL sA = sel_registerName("getBool:withOptions:");
    SEL sB = sel_registerName("getBool:withOptions:withDefault:");
    SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");

    if (!gOrigBool[cn]) {
        if (class_getInstanceMethod(cls, sA)) {
            IMP orig = NULL;
            MSHookMessageEx(cls, sA, (IMP)h_getBoolWithOptions, &orig);
            if (orig) { gOrigBool[cn] = [NSValue valueWithPointer:(const void*)orig]; gHooked++; }
        }
    }
    if (!gOrigBoolWD[cn]) {
        if (class_getInstanceMethod(cls, sB)) {
            IMP orig = NULL;
            MSHookMessageEx(cls, sB, (IMP)h_getBoolWithOptionsDefault, &orig);
            if (orig) gOrigBoolWD[cn] = [NSValue valueWithPointer:(const void*)orig];
        }
    }
    if (!orig_setScrollable && class_getInstanceMethod(cls, sC)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sC, (IMP)h_setShouldEnableScrollableTabBar, &orig);
        if (orig) orig_setScrollable = (SetScrollIMP)orig;
    }
}

static void FBGRMCInstall(void) {
    FBGRMCInit();
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
    // Fallback scan for scrollable tab bar
    if (!orig_setScrollable) {
        SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");
        unsigned int n = 0; Class *all = objc_copyClassList(&n);
        for (unsigned i = 0; i < n && !orig_setScrollable; i++)
            if (class_getInstanceMethod(all[i], sC)) FBGRMCHookClass(all[i]);
        free(all);
    }
    FBGRLogAppend([NSString stringWithFormat:@"MCGateHooks installed on %lu classes", (unsigned long)gHooked]);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) { FBGRMCInstall(); }

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    FBGRMCInit();
    return [NSString stringWithFormat:
        @"hookedClasses=%lu\nscrollable=%@\noverrides=%lu\nclasses=[%@]",
        (unsigned long)gHooked,
        orig_setScrollable ? @"YES" : @"NO",
        (unsigned long)FBGRGateAllOverrideSlotIds().count,
        [gOrigBool.allKeys componentsJoinedByString:@","]];
}

__attribute__((constructor))
static void FBGRMCGateHooksCtor(void) {
    @autoreleasepool { FBGRMCInstall(); }
}
