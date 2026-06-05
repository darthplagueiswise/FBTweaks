#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"

typedef BOOL (*GetBool4IMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*GetBool5IMP)(id, SEL, mc_bool_param_t, id, BOOL);

typedef struct {
    Class hookClass;
    SEL sel;
    unsigned int argc;
    IMP orig;
} FBGRMCHook;

#define FBGR_MC_MAX_HOOKS 512
static FBGRMCHook gHooks[FBGR_MC_MAX_HOOKS];
static NSUInteger gHookN = 0;
static BOOL gInstalled = NO;
static BOOL gInstalling = NO;
static __thread BOOL gGuard = NO;

static BOOL FBGRImageLooksRelevant(const char *imgC) {
    if (!imgC) return NO;
    NSString *img = [NSString stringWithUTF8String:imgC] ?: @"";
    return [img containsString:@"/Facebook.app/Facebook"] ||
           [img containsString:@"/FBSharedFramework.framework/FBSharedFramework"] ||
           [img containsString:@"/MobileConfig"] ||
           [img containsString:@"/FBMobileConfig"] ||
           [img containsString:@"/Frameworks/"];
}

static FBGRMCHook *FBGRFindHook(Class hookClass, SEL sel) {
    for (NSUInteger i = 0; i < gHookN; i++) if (gHooks[i].hookClass == hookClass && gHooks[i].sel == sel) return &gHooks[i];
    return NULL;
}

static uint64_t FBGRSlotFromParam(mc_bool_param_t p) { return p.value; }

static BOOL h_getBool4(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    uint64_t slot = FBGRSlotFromParam(p);
    if (FBGRGateIsSet(slot)) return FBGRGateGet(slot);
    if (gGuard) return NO;
    Class hookClass = object_getClass(self);
    FBGRMCHook *e = FBGRFindHook(hookClass, _cmd);
    if (!e) e = FBGRFindHook([self class], _cmd);
    GetBool4IMP orig = e ? (GetBool4IMP)e->orig : NULL;
    gGuard = YES;
    BOOL r = orig ? orig(self, _cmd, p, opts) : NO;
    gGuard = NO;
    return r;
}

static BOOL h_getBool5(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    uint64_t slot = FBGRSlotFromParam(p);
    if (FBGRGateIsSet(slot)) return FBGRGateGet(slot);
    if (gGuard) return def;
    Class hookClass = object_getClass(self);
    FBGRMCHook *e = FBGRFindHook(hookClass, _cmd);
    if (!e) e = FBGRFindHook([self class], _cmd);
    GetBool5IMP orig = e ? (GetBool5IMP)e->orig : NULL;
    gGuard = YES;
    BOOL r = orig ? orig(self, _cmd, p, opts, def) : def;
    gGuard = NO;
    return r;
}

static void FBGRHookMethod(Class cls, SEL sel, BOOL classMethod) {
    if (!cls || !sel || gHookN >= FBGR_MC_MAX_HOOKS) return;
    Method m = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m) return;
    unsigned int argc = method_getNumberOfArguments(m);
    if (argc != 4 && argc != 5) return;
    Class hookClass = classMethod ? object_getClass(cls) : cls;
    if (!hookClass || FBGRFindHook(hookClass, sel)) return;
    IMP orig = NULL;
    MSHookMessageEx(hookClass, sel, argc == 5 ? (IMP)h_getBool5 : (IMP)h_getBool4, &orig);
    if (!orig) return;
    gHooks[gHookN++] = (FBGRMCHook){ hookClass, sel, argc, orig };
}

static void FBGRHookClass(Class cls) {
    if (!cls) return;
    SEL selectors[] = {
        sel_registerName("getBool:withOptions:"),
        sel_registerName("getBool:withOptions:withDefault:"),
        sel_registerName("getBool:withOptions:defaultValue:"),
        sel_registerName("getBoolForParam:withOptions:"),
        sel_registerName("getBoolForParam:withOptions:withDefault:"),
    };
    for (NSUInteger i = 0; i < sizeof(selectors) / sizeof(selectors[0]); i++) {
        FBGRHookMethod(cls, selectors[i], NO);
        FBGRHookMethod(cls, selectors[i], YES);
    }
}

static void FBGRInstallInternal(void) {
    if (gInstalled || gInstalling) return;
    gInstalling = YES;
    FBGRGateWarmCacheFromPrefs();

    NSArray<NSString *> *known = @[
        @"FBMobileConfigContextManager", @"FBMobileConfigUserSessionContextManager", @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigFBTAPI", @"FBMobileConfigFBTContextManager", @"FBMobileConfigAPI", @"FBMobileConfigGlobalContext",
        @"FBMobileConfigContextObjcImpl", @"FBMobileConfigAdminIDContextManager", @"RCTMobileConfigNative", @"MobileConfigModule"
    ];
    for (NSString *name in known) FBGRHookClass(NSClassFromString(name));

    int n = objc_getClassList(NULL, 0);
    if (n > 0) {
        Class *classes = (Class *)calloc((NSUInteger)n, sizeof(Class));
        n = objc_getClassList(classes, n);
        for (int i = 0; i < n; i++) {
            Class cls = classes[i];
            if (!FBGRImageLooksRelevant(class_getImageName(cls))) continue;
            NSString *cn = NSStringFromClass(cls).lowercaseString;
            if (![cn containsString:@"mobileconfig"] && ![cn containsString:@"config"] && ![cn containsString:@"gate"] && ![cn containsString:@"experiment"]) continue;
            FBGRHookClass(cls);
        }
        free(classes);
    }

    gInstalled = YES;
    gInstalling = NO;
    FBGRLogAppend([NSString stringWithFormat:@"MC hooks installed: %lu hooks", (unsigned long)gHookN]);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) {
    if ([NSThread isMainThread]) FBGRInstallInternal();
    else dispatch_sync(dispatch_get_main_queue(), ^{ FBGRInstallInternal(); });
}

extern "C" void FBGRMCGateHooksApplyPersistedOverrides(void) {
    FBGRGateWarmCacheFromPrefs();
    FBGRMCGateHooksEnsureInstalled();
}

extern "C" void FBGRMCGateCacheRefresh(void) {
    FBGRGateWarmCacheFromPrefs();
}

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\nhooks=%lu\noverrides=%lu\nmode=on-demand real scan", gInstalled ? @"YES" : @"NO", (unsigned long)gHookN, (unsigned long)FBGRGateAllOverrideSlotIds().count];
}
