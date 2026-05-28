// FBGRMCGateHooks.xm — generic MobileConfig getBool: interceptor.
//
// REENTRANCY GUARD — mandatory.
// Root cause (crash depth=2053):
//   h_getBoolWithOptions → orig() → mobileconfig::unitTypeFromParameter
//   → getBool:withOptions: (internal MC call) → h_getBoolWithOptions → ...
// The original MobileConfig getBool: implementation calls itself recursively
// via unitTypeFromParameter. Without a guard, our hook amplifies that into
// an infinite loop that blows the stack.
// Fix: __thread (TLS) BOOL — each thread has its own flag, zero cost when
// there is no reentrancy, O(1) check when there is.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"

// ── Reentrancy guard (thread-local) ──────────────────────────────────────────
// __thread is a GCC/Clang TLS extension, valid in ObjC++ (.xm).
static __thread BOOL gFBGRMCHookGuard = NO;

// ── Override resolution ───────────────────────────────────────────────────────
static inline BOOL FBGRShouldOverride(uint64_t slotId, BOOL *outValue) {
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
static NSUInteger   gHooked = 0;
static dispatch_once_t gOnce;

static void FBGRMCInit(void) {
    dispatch_once(&gOnce, ^{
        gOrigBool   = [NSMutableDictionary dictionaryWithCapacity:8];
        gOrigBoolWD = [NSMutableDictionary dictionaryWithCapacity:8];
    });
}

// ── getBool:withOptions: trampoline ───────────────────────────────────────────
static BOOL h_getBoolWithOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    // Guard: if we're already inside this hook on this thread, go straight to orig.
    // This breaks the recursion caused by mobileconfig::unitTypeFromParameter
    // calling getBool:withOptions: internally.
    if (gFBGRMCHookGuard) {
        NSString *cls = NSStringFromClass([self class]);
        GetBoolIMP orig = gOrigBool[cls] ? (GetBoolIMP)[gOrigBool[cls] pointerValue] : NULL;
        return orig ? orig(self, _cmd, p, opts) : NO;
    }

    gFBGRMCHookGuard = YES;

    BOOL forced = NO;
    BOOL result;
    if (FBGRShouldOverride(p.value, &forced)) {
        FBGRLogAppend([NSString stringWithFormat:@"MC getBool slotId=%llu → %@",
                       (unsigned long long)p.value, forced ? @"YES" : @"NO"]);
        result = forced;
    } else {
        NSString *cls = NSStringFromClass([self class]);
        GetBoolIMP orig = gOrigBool[cls] ? (GetBoolIMP)[gOrigBool[cls] pointerValue] : NULL;
        result = orig ? orig(self, _cmd, p, opts) : NO;
    }

    gFBGRMCHookGuard = NO;
    return result;
}

// ── getBool:withOptions:withDefault: trampoline ───────────────────────────────
static BOOL h_getBoolWithOptionsDefault(id self, SEL _cmd,
                                        mc_bool_param_t p, id opts, BOOL def) {
    if (gFBGRMCHookGuard) {
        NSString *cls = NSStringFromClass([self class]);
        GetBoolWDIMP orig = gOrigBoolWD[cls] ? (GetBoolWDIMP)[gOrigBoolWD[cls] pointerValue] : NULL;
        return orig ? orig(self, _cmd, p, opts, def) : def;
    }

    gFBGRMCHookGuard = YES;

    BOOL forced = NO;
    BOOL result;
    if (FBGRShouldOverride(p.value, &forced)) {
        result = forced;
    } else {
        NSString *cls = NSStringFromClass([self class]);
        GetBoolWDIMP orig = gOrigBoolWD[cls] ? (GetBoolWDIMP)[gOrigBoolWD[cls] pointerValue] : NULL;
        result = orig ? orig(self, _cmd, p, opts, def) : def;
    }

    gFBGRMCHookGuard = NO;
    return result;
}

// ── setShouldEnableScrollableTabBar: trampoline ───────────────────────────────
static void h_setShouldEnableScrollableTabBar(id self, SEL _cmd, BOOL v) {
    BOOL forced;
    if (!gFBGRMCHookGuard && FBGRShouldOverride(1217, &forced) && forced) v = YES;
    if (orig_setScrollable) orig_setScrollable(self, _cmd, v);
}

// ── Hook installation ─────────────────────────────────────────────────────────
static void FBGRMCHookClass(Class cls) {
    NSString *cn = NSStringFromClass(cls);
    SEL sA = sel_registerName("getBool:withOptions:");
    SEL sB = sel_registerName("getBool:withOptions:withDefault:");
    SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");

    if (!gOrigBool[cn] && class_getInstanceMethod(cls, sA)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sA, (IMP)h_getBoolWithOptions, &orig);
        if (orig) { gOrigBool[cn] = [NSValue valueWithPointer:(const void*)orig]; gHooked++; }
    }
    if (!gOrigBoolWD[cn] && class_getInstanceMethod(cls, sB)) {
        IMP orig = NULL;
        MSHookMessageEx(cls, sB, (IMP)h_getBoolWithOptionsDefault, &orig);
        if (orig) gOrigBoolWD[cn] = [NSValue valueWithPointer:(const void*)orig];
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
    if (!orig_setScrollable) {
        SEL sC = sel_registerName("setShouldEnableScrollableTabBar:");
        unsigned int n = 0; Class *all = objc_copyClassList(&n);
        for (unsigned i = 0; i < n && !orig_setScrollable; i++)
            if (class_getInstanceMethod(all[i], sC)) FBGRMCHookClass(all[i]);
        free(all);
    }
    FBGRLogAppend([NSString stringWithFormat:@"MCGateHooks: %lu classes hooked", (unsigned long)gHooked]);
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
