#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"
#import <string.h>

typedef BOOL (*GetBoolIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GetBoolDefaultIMP)(id, SEL, mc_bool_param_t, id, BOOL);

typedef struct { Class cls; IMP getBoolOrig; IMP getBoolDefaultOrig; } FBGRMCHookedClass;
#define FBGR_MC_MAX_CLASSES 32
static FBGRMCHookedClass gClasses[FBGR_MC_MAX_CLASSES];
static NSUInteger gClassN = 0;
static BOOL gInstalled = NO;
static BOOL gInstalling = NO;
static __thread BOOL gGuard = NO;

static FBGRMCHookedClass *FBGRFindClass(Class cls) {
    for (NSUInteger i = 0; i < gClassN; i++) if (gClasses[i].cls == cls) return &gClasses[i];
    return NULL;
}

static BOOL h_getBool(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    if (gGuard) return NO;
    if (FBGRGateIsSet(p.value)) return FBGRGateGet(p.value);
    FBGRMCHookedClass *e = FBGRFindClass(object_getClass(self));
    GetBoolIMP orig = e ? (GetBoolIMP)e->getBoolOrig : NULL;
    gGuard = YES;
    BOOL r = orig ? orig(self, _cmd, p, opts) : NO;
    gGuard = NO;
    return r;
}

static BOOL h_getBoolDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    if (gGuard) return def;
    if (FBGRGateIsSet(p.value)) return FBGRGateGet(p.value);
    FBGRMCHookedClass *e = FBGRFindClass(object_getClass(self));
    GetBoolDefaultIMP orig = e ? (GetBoolDefaultIMP)e->getBoolDefaultOrig : NULL;
    gGuard = YES;
    BOOL r = orig ? orig(self, _cmd, p, opts, def) : def;
    gGuard = NO;
    return r;
}

static void FBGRHookOne(Class cls) {
    if (!cls || FBGRFindClass(cls) || gClassN >= FBGR_MC_MAX_CLASSES) return;
    SEL a = sel_registerName("getBool:withOptions:");
    SEL b = sel_registerName("getBool:withOptions:withDefault:");
    Method ma = class_getInstanceMethod(cls, a);
    Method mb = class_getInstanceMethod(cls, b);
    if (!ma && !mb) return;
    FBGRMCHookedClass *e = &gClasses[gClassN]; memset(e, 0, sizeof(*e)); e->cls = cls;
    if (ma) { IMP orig = NULL; MSHookMessageEx(cls, a, (IMP)h_getBool, &orig); e->getBoolOrig = orig; }
    if (mb) { IMP orig = NULL; MSHookMessageEx(cls, b, (IMP)h_getBoolDefault, &orig); e->getBoolDefaultOrig = orig; }
    gClassN++;
}

static void FBGRInstallInternal(void) {
    if (gInstalled || gInstalling) return;
    gInstalling = YES;
    FBGRGateWarmCacheFromPrefs();
    NSArray<NSString *> *names = @[
        @"FBMobileConfigContextManager", @"FBMobileConfigUserSessionContextManager", @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigFBTAPI", @"FBMobileConfigFBTContextManager", @"FBMobileConfigAPI", @"FBMobileConfigGlobalContext",
        @"FBMobileConfigContextObjcImpl", @"FBMobileConfigAdminIDContextManager", @"RCTMobileConfigNative", @"MobileConfigModule"
    ];
    for (NSString *n in names) FBGRHookOne(NSClassFromString(n));
    gInstalled = YES;
    gInstalling = NO;
    FBGRLogAppend([NSString stringWithFormat:@"MC hooks installed on %lu classes", (unsigned long)gClassN]);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ FBGRInstallInternal(); });
}

extern "C" void FBGRMCGateHooksApplyPersistedOverrides(void) {
    FBGRGateWarmCacheFromPrefs();
    if (FBGRGateAllOverrideSlotIds().count) FBGRMCGateHooksEnsureInstalled();
}

extern "C" void FBGRMCGateCacheRefresh(void) {
    FBGRGateWarmCacheFromPrefs();
}

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\nclasses=%lu\noverrides=%lu", gInstalled ? @"YES" : @"NO", (unsigned long)gClassN, (unsigned long)FBGRGateAllOverrideSlotIds().count];
}
