#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import <string.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRLog.h"

typedef BOOL (*Param1IMP)(id, SEL, mc_bool_param_t);
typedef BOOL (*ParamDefaultIMP)(id, SEL, mc_bool_param_t, BOOL);
typedef BOOL (*ParamOptionsIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*ParamOptionsDefaultIMP)(id, SEL, mc_bool_param_t, id, BOOL);
typedef BOOL (*Key1IMP)(id, SEL, id);
typedef BOOL (*KeyDefaultIMP)(id, SEL, id, BOOL);

typedef NS_ENUM(uint8_t, FBGRMCSigKind) {
    FBGRMCSigNone = 0,
    FBGRMCSigParam1 = 1,
    FBGRMCSigParamDefault = 2,
    FBGRMCSigParamOptions = 3,
    FBGRMCSigParamOptionsDefault = 4,
    FBGRMCSigKey1 = 5,
    FBGRMCSigKeyDefault = 6,
};

typedef struct {
    Class cls;
    SEL sel;
    FBGRMCSigKind kind;
    IMP orig;
    BOOL classMethod;
} FBGRMCRecord;

#define FBGR_MC_MAX_RECORDS 256
static FBGRMCRecord gRecords[FBGR_MC_MAX_RECORDS];
static NSUInteger gRecordCount = 0;
static BOOL gInstalled = NO;
static BOOL gInstalling = NO;
static BOOL gRetryWindowScheduled = NO;
static NSUInteger gInstallPasses = 0;
static NSUInteger gScannedMethods = 0;
static NSUInteger gRejectedMethods = 0;
static __thread BOOL gGuard = NO;

typedef BOOL (*MCGetBoolSlotFn)(uint64_t slot);
static MCGetBoolSlotFn orig_mc_getBoolDefault = NULL;
static NSUInteger gFunctionHookCount = 0;

static FBGRMCRecord *FBGRFindRecord(Class cls, SEL sel, FBGRMCSigKind kind) {
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        for (NSUInteger i = 0; i < gRecordCount; i++) {
            if (gRecords[i].cls == c && gRecords[i].sel == sel && gRecords[i].kind == kind) return &gRecords[i];
        }
    }
    return NULL;
}

static NSNumber *FBGRForcedForSlot(uint64_t slot) {
    if (FBGRGateIsSet(slot)) return @(FBGRGateGet(slot));
    return nil;
}

static NSNumber *FBGRForcedForKey(id keyObject) {
    if ([keyObject isKindOfClass:NSNumber.class]) return FBGRForcedForSlot([(NSNumber *)keyObject unsignedLongLongValue]);
    if (![keyObject isKindOfClass:NSString.class]) return nil;
    BOOL found = NO;
    uint64_t slot = [[FBGRMCCatalog shared] slotIdForKey:(NSString *)keyObject found:&found];
    return found ? FBGRForcedForSlot(slot) : nil;
}

static BOOL FBGRCallParam1(id self, SEL _cmd, mc_bool_param_t p) {
    FBGRMCRecord *r = FBGRFindRecord(object_getClass(self), _cmd, FBGRMCSigParam1);
    return r && r->orig ? ((Param1IMP)r->orig)(self, _cmd, p) : NO;
}
static BOOL FBGRCallParamDefault(id self, SEL _cmd, mc_bool_param_t p, BOOL def) {
    FBGRMCRecord *r = FBGRFindRecord(object_getClass(self), _cmd, FBGRMCSigParamDefault);
    return r && r->orig ? ((ParamDefaultIMP)r->orig)(self, _cmd, p, def) : def;
}
static BOOL FBGRCallParamOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    FBGRMCRecord *r = FBGRFindRecord(object_getClass(self), _cmd, FBGRMCSigParamOptions);
    return r && r->orig ? ((ParamOptionsIMP)r->orig)(self, _cmd, p, opts) : NO;
}
static BOOL FBGRCallParamOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    FBGRMCRecord *r = FBGRFindRecord(object_getClass(self), _cmd, FBGRMCSigParamOptionsDefault);
    return r && r->orig ? ((ParamOptionsDefaultIMP)r->orig)(self, _cmd, p, opts, def) : def;
}
static BOOL FBGRCallKey1(id self, SEL _cmd, id key) {
    FBGRMCRecord *r = FBGRFindRecord(object_getClass(self), _cmd, FBGRMCSigKey1);
    return r && r->orig ? ((Key1IMP)r->orig)(self, _cmd, key) : NO;
}
static BOOL FBGRCallKeyDefault(id self, SEL _cmd, id key, BOOL def) {
    FBGRMCRecord *r = FBGRFindRecord(object_getClass(self), _cmd, FBGRMCSigKeyDefault);
    return r && r->orig ? ((KeyDefaultIMP)r->orig)(self, _cmd, key, def) : def;
}

static BOOL h_param1(id self, SEL _cmd, mc_bool_param_t p) {
    NSNumber *forced = FBGRForcedForSlot(p.value);
    if (forced) return forced.boolValue;
    if (gGuard) return NO;
    gGuard = YES; BOOL out = FBGRCallParam1(self, _cmd, p); gGuard = NO; return out;
}
static BOOL h_paramDefault(id self, SEL _cmd, mc_bool_param_t p, BOOL def) {
    NSNumber *forced = FBGRForcedForSlot(p.value);
    if (forced) return forced.boolValue;
    if (gGuard) return def;
    gGuard = YES; BOOL out = FBGRCallParamDefault(self, _cmd, p, def); gGuard = NO; return out;
}
static BOOL h_paramOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    NSNumber *forced = FBGRForcedForSlot(p.value);
    if (forced) return forced.boolValue;
    if (gGuard) return NO;
    gGuard = YES; BOOL out = FBGRCallParamOptions(self, _cmd, p, opts); gGuard = NO; return out;
}
static BOOL h_paramOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    NSNumber *forced = FBGRForcedForSlot(p.value);
    if (forced) return forced.boolValue;
    if (gGuard) return def;
    gGuard = YES; BOOL out = FBGRCallParamOptionsDefault(self, _cmd, p, opts, def); gGuard = NO; return out;
}
static BOOL h_key1(id self, SEL _cmd, id key) {
    NSNumber *forced = FBGRForcedForKey(key);
    if (forced) return forced.boolValue;
    if (gGuard) return NO;
    gGuard = YES; BOOL out = FBGRCallKey1(self, _cmd, key); gGuard = NO; return out;
}
static BOOL h_keyDefault(id self, SEL _cmd, id key, BOOL def) {
    NSNumber *forced = FBGRForcedForKey(key);
    if (forced) return forced.boolValue;
    if (gGuard) return def;
    gGuard = YES; BOOL out = FBGRCallKeyDefault(self, _cmd, key, def); gGuard = NO; return out;
}
static BOOL h_mc_getBoolSlot(uint64_t slot) {
    NSNumber *forced = FBGRForcedForSlot(slot);
    if (forced) return forced.boolValue;
    return orig_mc_getBoolDefault ? orig_mc_getBoolDefault(slot) : NO;
}

static NSString *FBGRArgType(Method m, unsigned int idx) {
    char buf[256]; memset(buf, 0, sizeof(buf)); method_getArgumentType(m, idx, buf, sizeof(buf));
    return [NSString stringWithUTF8String:buf] ?: @"";
}
static NSString *FBGRReturnType(Method m) {
    char buf[32]; memset(buf, 0, sizeof(buf)); method_getReturnType(m, buf, sizeof(buf));
    return [NSString stringWithUTF8String:buf] ?: @"";
}
static BOOL FBGRReturnIsBool(Method m) {
    NSString *t = FBGRReturnType(m);
    return [t isEqualToString:@"B"] || [t isEqualToString:@"c"] || [t isEqualToString:@"C"];
}
static BOOL FBGRArgIsObject(Method m, unsigned int idx) {
    NSString *t = FBGRArgType(m, idx);
    return [t hasPrefix:@"@"] || [t hasPrefix:@"?"];
}
static BOOL FBGRArgIsBool(Method m, unsigned int idx) {
    NSString *t = FBGRArgType(m, idx);
    return [t isEqualToString:@"B"] || [t isEqualToString:@"c"] || [t isEqualToString:@"C"];
}
static BOOL FBGRArgIsMCBoolParam(Method m, unsigned int idx) {
    NSString *t = FBGRArgType(m, idx);
    if (!t.length) return NO;
    if ([t containsString:@"mc_bool_param_t"]) return YES;
    if ([t containsString:@"mc_sessionbased_bool_param_t"]) return YES;
    if ([t containsString:@"mc_sessionless_bool_param_t"]) return YES;
    if ([t containsString:@"mc_adminID_bool_param_t"]) return YES;
    return ([t containsString:@"_bool_param_t"] && [t containsString:@"=Q"]);
}
static BOOL FBGRSelectorLooksKeyBased(SEL sel) {
    NSString *s = NSStringFromSelector(sel).lowercaseString;
    return [s containsString:@"bool"] && ([s containsString:@"key"] || [s containsString:@"param"] || [s containsString:@"config"] || [s containsString:@"gate"]);
}

static FBGRMCSigKind FBGRKindForMethod(Method m, BOOL allowKeyMethods) {
    if (!m || !FBGRReturnIsBool(m)) return FBGRMCSigNone;
    unsigned int argc = method_getNumberOfArguments(m);
    if (argc == 3 && FBGRArgIsMCBoolParam(m, 2)) return FBGRMCSigParam1;
    if (argc == 4 && FBGRArgIsMCBoolParam(m, 2) && FBGRArgIsBool(m, 3)) return FBGRMCSigParamDefault;
    if (argc == 4 && FBGRArgIsMCBoolParam(m, 2) && FBGRArgIsObject(m, 3)) return FBGRMCSigParamOptions;
    if (argc == 5 && FBGRArgIsMCBoolParam(m, 2) && FBGRArgIsObject(m, 3) && FBGRArgIsBool(m, 4)) return FBGRMCSigParamOptionsDefault;
    if (allowKeyMethods && FBGRSelectorLooksKeyBased(method_getName(m)) && argc == 3 && FBGRArgIsObject(m, 2)) return FBGRMCSigKey1;
    if (allowKeyMethods && FBGRSelectorLooksKeyBased(method_getName(m)) && argc == 4 && FBGRArgIsObject(m, 2) && FBGRArgIsBool(m, 3)) return FBGRMCSigKeyDefault;
    return FBGRMCSigNone;
}

static IMP FBGRReplacementForKind(FBGRMCSigKind kind) {
    switch (kind) {
        case FBGRMCSigParam1: return (IMP)h_param1;
        case FBGRMCSigParamDefault: return (IMP)h_paramDefault;
        case FBGRMCSigParamOptions: return (IMP)h_paramOptions;
        case FBGRMCSigParamOptionsDefault: return (IMP)h_paramOptionsDefault;
        case FBGRMCSigKey1: return (IMP)h_key1;
        case FBGRMCSigKeyDefault: return (IMP)h_keyDefault;
        default: return NULL;
    }
}

static void FBGRHookMethod(Class ownerClass, Method m, FBGRMCSigKind kind, BOOL classMethod) {
    if (!ownerClass || !m || kind == FBGRMCSigNone || gRecordCount >= FBGR_MC_MAX_RECORDS) return;
    SEL sel = method_getName(m);
    Class hookClass = classMethod ? object_getClass(ownerClass) : ownerClass;
    if (!hookClass) return;
    for (NSUInteger i = 0; i < gRecordCount; i++) {
        if (gRecords[i].cls == hookClass && gRecords[i].sel == sel && gRecords[i].kind == kind) return;
    }
    IMP repl = FBGRReplacementForKind(kind);
    if (!repl) return;
    IMP orig = NULL;
    MSHookMessageEx(hookClass, sel, repl, &orig);
    if (!orig) return;
    gRecords[gRecordCount++] = (FBGRMCRecord){ hookClass, sel, kind, orig, classMethod };
}

static void FBGRHookClassByTypes(NSString *className, BOOL allowKeyMethods) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        gScannedMethods++;
        FBGRMCSigKind kind = FBGRKindForMethod(methods[i], allowKeyMethods);
        if (kind == FBGRMCSigNone) gRejectedMethods++;
        FBGRHookMethod(cls, methods[i], kind, NO);
    }
    if (methods) free(methods);

    count = 0;
    methods = class_copyMethodList(object_getClass(cls), &count);
    for (unsigned int i = 0; i < count; i++) {
        gScannedMethods++;
        FBGRMCSigKind kind = FBGRKindForMethod(methods[i], allowKeyMethods);
        if (kind == FBGRMCSigNone) gRejectedMethods++;
        FBGRHookMethod(cls, methods[i], kind, YES);
    }
    if (methods) free(methods);
}

static void FBGRInstallFunctionHookIfPresent(const char *symbol) {
    if (!symbol || orig_mc_getBoolDefault) return;
    void *addr = MSFindSymbol(NULL, symbol);
    if (!addr) addr = dlsym(RTLD_DEFAULT, symbol);
    if (!addr) return;
    MSHookFunction(addr, (void *)h_mc_getBoolSlot, (void **)&orig_mc_getBoolDefault);
    if (orig_mc_getBoolDefault) gFunctionHookCount++;
}

static void FBGRInstall(void) {
    if (gInstalling) return;
    gInstalling = YES;
gInstallPasses++;
    FBGRGateWarmCacheFromPrefs();
    [[FBGRMCCatalog shared] loadIfNeeded];

    for (NSString *name in @[
        @"FBMobileConfigContextManager",
        @"FBMobileConfigContextObjcImpl",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigAdminIDContextManager",
        @"FBMobileConfigStartupConfigs",
        @"FBMobileConfigStartupConfigsDeprecated"
    ]) FBGRHookClassByTypes(name, NO);

    for (NSString *name in @[
        @"RCTMobileConfigNative",
        @"NativeMobileConfigModuleSpecBase"
    ]) FBGRHookClassByTypes(name, YES);

    FBGRInstallFunctionHookIfPresent("__ZN12mobileconfig14getBoolDefaultEy");
    FBGRInstallFunctionHookIfPresent("_ZN12mobileconfig14getBoolDefaultEy");

    gInstalled = (gRecordCount > 0 || gFunctionHookCount > 0);
    gInstalling = NO;
    FBGRLogAppend([NSString stringWithFormat:@"MC exact hooks install pass %lu: installed=%@ records=%lu function=%lu scanned=%lu rejected=%lu overrides=%lu", (unsigned long)gInstallPasses, gInstalled ? @"YES" : @"NO", (unsigned long)gRecordCount, (unsigned long)gFunctionHookCount, (unsigned long)gScannedMethods, (unsigned long)gRejectedMethods, (unsigned long)FBGRGateAllOverrideSlotIds().count]);
}

static void FBGRScheduleRetry(NSTimeInterval delay, BOOL lastPass) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        FBGRInstall();
        if (lastPass) gRetryWindowScheduled = NO;
    });
}

static void FBGRScheduleRetryWindow(void) {
    if (gRetryWindowScheduled) return;

    gRetryWindowScheduled = YES;
    FBGRScheduleRetry(0.75, NO);
    FBGRScheduleRetry(2.0, NO);
    FBGRScheduleRetry(5.0, YES);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) {
    FBGRInstall();
    FBGRScheduleRetryWindow();
}

extern "C" void FBGRMCGateHooksApplyPersistedOverrides(void) {
    FBGRGateWarmCacheFromPrefs();
    FBGRMCGateHooksEnsureInstalled();
}

extern "C" void FBGRMCGateCacheRefresh(void) {
    FBGRGateWarmCacheFromPrefs();
}

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\ninstall passes=%lu\nretry window=%@\nrecords=%lu\nfunction hooks=%lu\nscanned methods=%lu\nrejected methods=%lu\noverrides=%lu\nstrategy=exact *_bool_param_t type-encoding hooks, repeatable late-class scan", gInstalled ? @"YES" : @"NO", (unsigned long)gInstallPasses, gRetryWindowScheduled ? @"active" : @"idle", (unsigned long)gRecordCount, (unsigned long)gFunctionHookCount, (unsigned long)gScannedMethods, (unsigned long)gRejectedMethods, (unsigned long)FBGRGateAllOverrideSlotIds().count];
}
