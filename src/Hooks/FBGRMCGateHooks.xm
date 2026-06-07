#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRLog.h"

typedef BOOL (*Key1IMP)(id, SEL, id);
typedef BOOL (*KeyDefaultIMP)(id, SEL, id, BOOL);
typedef BOOL (*Param1IMP)(id, SEL, mc_bool_param_t);
typedef BOOL (*ParamDefaultIMP)(id, SEL, mc_bool_param_t, BOOL);
typedef BOOL (*ParamOptionsIMP)(id, SEL, mc_bool_param_t, id);
typedef BOOL (*ParamOptionsDefaultIMP)(id, SEL, mc_bool_param_t, id, BOOL);

typedef NS_ENUM(uint8_t, FBGRMCSigKind) {
    FBGRMCSigNone = 0,
    FBGRMCSigKey1 = 1,
    FBGRMCSigKeyDefault = 2,
    FBGRMCSigParam1 = 3,
    FBGRMCSigParamDefault = 4,
    FBGRMCSigParamOptions = 5,
    FBGRMCSigParamOptionsDefault = 6,
};

typedef struct { Class cls; SEL sel; FBGRMCSigKind kind; BOOL classMethod; IMP orig; } FBGRMCRecord;
#define FBGR_MC_MAX_RECORDS 768
static FBGRMCRecord gRecords[FBGR_MC_MAX_RECORDS];
static NSUInteger gRecordCount = 0;
static BOOL gInstalled = NO;
static BOOL gInstalling = NO;
static NSUInteger gScannedClasses = 0;
static NSUInteger gFunctionHookCount = 0;
static __thread BOOL gGuard = NO;

typedef BOOL (*MCGetBoolDefaultFn)(uint64_t slot);
typedef BOOL (*IgluGetBoolFn)(void *self, const char *key);
static MCGetBoolDefaultFn orig_mc_getBoolDefault = NULL;
static IgluGetBoolFn orig_iglu_getBool = NULL;

static FBGRMCRecord *FBGRMCFindRecordExact(Class cls, SEL sel, FBGRMCSigKind kind) {
    for (NSUInteger i = 0; i < gRecordCount; i++) {
        if (gRecords[i].cls == cls && gRecords[i].sel == sel && gRecords[i].kind == kind) return &gRecords[i];
    }
    return NULL;
}

static FBGRMCRecord *FBGRMCFindRecordForReceiver(id self, SEL sel, FBGRMCSigKind kind) {
    Class cls = object_getClass(self);
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        FBGRMCRecord *r = FBGRMCFindRecordExact(c, sel, kind);
        if (r) return r;
    }
    return NULL;
}

static NSNumber *FBGRMCForcedForSlot(uint64_t slot) {
    if (FBGRGateIsSet(slot)) return @(FBGRGateGet(slot));
    return nil;
}

static NSNumber *FBGRMCForcedForKey(id keyObject) {
    if ([keyObject isKindOfClass:NSNumber.class]) return FBGRMCForcedForSlot([(NSNumber *)keyObject unsignedLongLongValue]);
    if (![keyObject isKindOfClass:NSString.class]) return nil;
    BOOL found = NO;
    uint64_t slot = [[FBGRMCCatalog shared] slotIdForKey:(NSString *)keyObject found:&found];
    return found ? FBGRMCForcedForSlot(slot) : nil;
}

static BOOL FBGRMCCallKey1(id self, SEL _cmd, id key) {
    FBGRMCRecord *r = FBGRMCFindRecordForReceiver(self, _cmd, FBGRMCSigKey1);
    Key1IMP orig = r ? (Key1IMP)r->orig : NULL;
    return orig ? orig(self, _cmd, key) : NO;
}

static BOOL FBGRMCCallKeyDefault(id self, SEL _cmd, id key, BOOL def) {
    FBGRMCRecord *r = FBGRMCFindRecordForReceiver(self, _cmd, FBGRMCSigKeyDefault);
    KeyDefaultIMP orig = r ? (KeyDefaultIMP)r->orig : NULL;
    return orig ? orig(self, _cmd, key, def) : def;
}

static BOOL FBGRMCCallParam1(id self, SEL _cmd, mc_bool_param_t p) {
    FBGRMCRecord *r = FBGRMCFindRecordForReceiver(self, _cmd, FBGRMCSigParam1);
    Param1IMP orig = r ? (Param1IMP)r->orig : NULL;
    return orig ? orig(self, _cmd, p) : NO;
}

static BOOL FBGRMCCallParamDefault(id self, SEL _cmd, mc_bool_param_t p, BOOL def) {
    FBGRMCRecord *r = FBGRMCFindRecordForReceiver(self, _cmd, FBGRMCSigParamDefault);
    ParamDefaultIMP orig = r ? (ParamDefaultIMP)r->orig : NULL;
    return orig ? orig(self, _cmd, p, def) : def;
}

static BOOL FBGRMCCallParamOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    FBGRMCRecord *r = FBGRMCFindRecordForReceiver(self, _cmd, FBGRMCSigParamOptions);
    ParamOptionsIMP orig = r ? (ParamOptionsIMP)r->orig : NULL;
    return orig ? orig(self, _cmd, p, opts) : NO;
}

static BOOL FBGRMCCallParamOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    FBGRMCRecord *r = FBGRMCFindRecordForReceiver(self, _cmd, FBGRMCSigParamOptionsDefault);
    ParamOptionsDefaultIMP orig = r ? (ParamOptionsDefaultIMP)r->orig : NULL;
    return orig ? orig(self, _cmd, p, opts, def) : def;
}

static BOOL h_key1(id self, SEL _cmd, id key) {
    NSNumber *forced = FBGRMCForcedForKey(key);
    if (forced) return forced.boolValue;
    if (gGuard) return NO;
    gGuard = YES;
    BOOL out = FBGRMCCallKey1(self, _cmd, key);
    gGuard = NO;
    return out;
}

static BOOL h_keyDefault(id self, SEL _cmd, id key, BOOL def) {
    NSNumber *forced = FBGRMCForcedForKey(key);
    if (forced) return forced.boolValue;
    if (gGuard) return def;
    gGuard = YES;
    BOOL out = FBGRMCCallKeyDefault(self, _cmd, key, def);
    gGuard = NO;
    return out;
}

static BOOL h_param1(id self, SEL _cmd, mc_bool_param_t p) {
    NSNumber *forced = FBGRMCForcedForSlot(p.value);
    if (forced) return forced.boolValue;
    if (gGuard) return NO;
    gGuard = YES;
    BOOL out = FBGRMCCallParam1(self, _cmd, p);
    gGuard = NO;
    return out;
}

static BOOL h_paramDefault(id self, SEL _cmd, mc_bool_param_t p, BOOL def) {
    NSNumber *forced = FBGRMCForcedForSlot(p.value);
    if (forced) return forced.boolValue;
    if (gGuard) return def;
    gGuard = YES;
    BOOL out = FBGRMCCallParamDefault(self, _cmd, p, def);
    gGuard = NO;
    return out;
}

static BOOL h_paramOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    NSNumber *forced = FBGRMCForcedForSlot(p.value);
    if (forced) return forced.boolValue;
    if (gGuard) return NO;
    gGuard = YES;
    BOOL out = FBGRMCCallParamOptions(self, _cmd, p, opts);
    gGuard = NO;
    return out;
}

static BOOL h_paramOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    NSNumber *forced = FBGRMCForcedForSlot(p.value);
    if (forced) return forced.boolValue;
    if (gGuard) return def;
    gGuard = YES;
    BOOL out = FBGRMCCallParamOptionsDefault(self, _cmd, p, opts, def);
    gGuard = NO;
    return out;
}

static BOOL h_mc_getBoolDefault(uint64_t slot) {
    NSNumber *forced = FBGRMCForcedForSlot(slot);
    if (forced) return forced.boolValue;
    return orig_mc_getBoolDefault ? orig_mc_getBoolDefault(slot) : NO;
}

static BOOL h_iglu_getBool(void *selfPtr, const char *key) {
    NSString *s = key ? [NSString stringWithUTF8String:key] : nil;
    NSNumber *forced = FBGRMCForcedForKey(s);
    if (forced) return forced.boolValue;
    return orig_iglu_getBool ? orig_iglu_getBool(selfPtr, key) : NO;
}

static NSString *FBGRArgType(Method m, unsigned int idx) {
    char buf[256]; memset(buf, 0, sizeof(buf));
    method_getArgumentType(m, idx, buf, sizeof(buf));
    return [NSString stringWithUTF8String:buf] ?: @"";
}

static BOOL FBGRReturnIsBool(Method m) {
    char buf[16]; memset(buf, 0, sizeof(buf));
    method_getReturnType(m, buf, sizeof(buf));
    return buf[0] == 'B' || buf[0] == 'c' || buf[0] == 'C';
}

static BOOL FBGRArgIsObject(Method m, unsigned int idx) {
    NSString *t = FBGRArgType(m, idx);
    return [t hasPrefix:@"@"] || [t hasPrefix:@"?"];
}

static FBGRMCSigKind FBGRKindForMethod(NSString *selName, Method m) {
    if (!FBGRReturnIsBool(m)) return FBGRMCSigNone;
    unsigned int argc = method_getNumberOfArguments(m);
    BOOL objFirst = argc > 2 ? FBGRArgIsObject(m, 2) : NO;

    if ([selName isEqualToString:@"getBool:"] || [selName isEqualToString:@"getBoolWithoutLogging:"] || [selName isEqualToString:@"boolValueForParamKey:"] || [selName isEqualToString:@"ig_boolForKey:"]) {
        if (argc == 3) return objFirst ? FBGRMCSigKey1 : FBGRMCSigParam1;
    }
    if ([selName isEqualToString:@"getBool:withDefault:"] || [selName isEqualToString:@"getBoolWithoutLogging:withDefault:"] || [selName isEqualToString:@"getBoolForParam:withDefault:"] || [selName isEqualToString:@"boolForParameter:withDefault:"] || [selName isEqualToString:@"getBoolValue:defaultValue:"] || [selName isEqualToString:@"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:"] || [selName isEqualToString:@"ig_boolForKey:defaultValue:"]) {
        if (argc == 4) return objFirst ? FBGRMCSigKeyDefault : FBGRMCSigParamDefault;
    }
    if ([selName isEqualToString:@"getBool:withOptions:"] || [selName isEqualToString:@"getBoolForParam:withOptions:"]) {
        if (argc == 4 && !objFirst) return FBGRMCSigParamOptions;
    }
    if ([selName isEqualToString:@"getBool:withOptions:withDefault:"] || [selName isEqualToString:@"getBool:withOptions:defaultValue:"] || [selName isEqualToString:@"getBoolForParam:withOptions:withDefault:"]) {
        if (argc == 5 && !objFirst) return FBGRMCSigParamOptionsDefault;
    }
    return FBGRMCSigNone;
}

static IMP FBGRReplacementForKind(FBGRMCSigKind kind) {
    switch (kind) {
        case FBGRMCSigKey1: return (IMP)h_key1;
        case FBGRMCSigKeyDefault: return (IMP)h_keyDefault;
        case FBGRMCSigParam1: return (IMP)h_param1;
        case FBGRMCSigParamDefault: return (IMP)h_paramDefault;
        case FBGRMCSigParamOptions: return (IMP)h_paramOptions;
        case FBGRMCSigParamOptionsDefault: return (IMP)h_paramOptionsDefault;
        default: return NULL;
    }
}

static NSArray<NSString *> *FBGRRelevantImagePaths(void) {
    NSMutableArray *paths = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *c = _dyld_get_image_name(i);
        if (!c) continue;
        NSString *p = [NSString stringWithUTF8String:c] ?: @"";
        if (([p containsString:@"/Facebook.app/Facebook"] && ![p hasSuffix:@".dylib"]) || [p containsString:@"/FBSharedFramework.framework/FBSharedFramework"]) {
            if (![paths containsObject:p]) [paths addObject:p];
        }
    }
    return paths;
}

static void FBGRHookMethod(Class cls, Method m, BOOL classMethod) {
    if (!cls || !m || gRecordCount >= FBGR_MC_MAX_RECORDS) return;
    SEL sel = method_getName(m);
    NSString *selName = NSStringFromSelector(sel);
    FBGRMCSigKind kind = FBGRKindForMethod(selName, m);
    if (kind == FBGRMCSigNone) return;

    Class hookClass = classMethod ? object_getClass(cls) : cls;
    if (!hookClass || FBGRMCFindRecordExact(hookClass, sel, kind)) return;

    IMP replacement = FBGRReplacementForKind(kind);
    if (!replacement) return;

    IMP orig = NULL;
    MSHookMessageEx(hookClass, sel, replacement, &orig);
    if (!orig) return;
    gRecords[gRecordCount++] = (FBGRMCRecord){ hookClass, sel, kind, classMethod, orig };
}

static void FBGRScanImageAndHook(NSString *imagePath) {
    if (!imagePath.length) return;
    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(imagePath.UTF8String, &classCount);
    if (!classNames) return;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classNames[i] ? objc_getClass(classNames[i]) : Nil;
        if (!cls) continue;
        gScannedClasses++;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int j = 0; methods && j < count; j++) FBGRHookMethod(cls, methods[j], NO);
        if (methods) free(methods);
        count = 0;
        methods = class_copyMethodList(object_getClass(cls), &count);
        for (unsigned int j = 0; methods && j < count; j++) FBGRHookMethod(cls, methods[j], YES);
        if (methods) free(methods);
    }
    free(classNames);
}

static void FBGRScanAndHookObjC(void) {
    for (NSString *path in FBGRRelevantImagePaths()) FBGRScanImageAndHook(path);
}

static void *FBGRFindRuntimeSymbol(const char *symbol) {
    if (!symbol) return NULL;
    void *addr = MSFindSymbol(NULL, symbol);
    if (!addr && symbol[0] == '_') addr = dlsym(RTLD_DEFAULT, symbol + 1);
    if (!addr) addr = dlsym(RTLD_DEFAULT, symbol);
    return addr;
}

static void FBGRHookFunctionIfFound(const char *symbol, void *replacement, void **orig) {
    if (!symbol || !replacement || !orig || *orig) return;
    void *addr = FBGRFindRuntimeSymbol(symbol);
    if (!addr) return;
    MSHookFunction(addr, replacement, orig);
    if (*orig) gFunctionHookCount++;
}

static void FBGRInstallFunctionHooks(void) {
    FBGRHookFunctionIfFound("__ZN12mobileconfig14getBoolDefaultEy", (void *)h_mc_getBoolDefault, (void **)&orig_mc_getBoolDefault);
    FBGRHookFunctionIfFound("__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc", (void *)h_iglu_getBool, (void **)&orig_iglu_getBool);
}

static void FBGRInstall(void) {
    if (gInstalled || gInstalling) return;
    gInstalling = YES;
    FBGRGateWarmCacheFromPrefs();
    [[FBGRMCCatalog shared] loadIfNeeded];
    FBGRInstallFunctionHooks();
    FBGRScanAndHookObjC();
    gInstalled = YES;
    gInstalling = NO;
    FBGRLogAppend([NSString stringWithFormat:@"MC hooks installed: objc=%lu functions=%lu scanned=%lu", (unsigned long)gRecordCount, (unsigned long)gFunctionHookCount, (unsigned long)gScannedClasses]);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) { FBGRInstall(); }
extern "C" void FBGRMCGateHooksApplyPersistedOverrides(void) { FBGRGateWarmCacheFromPrefs(); if (FBGRGateAllOverrideSlotIds().count > 0) FBGRInstall(); }
extern "C" void FBGRMCGateCacheRefresh(void) { FBGRGateWarmCacheFromPrefs(); }

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\nobjc hooks=%lu\nfunction hooks=%lu\nscanned classes=%lu\noverrides=%lu\nstrategy: MSHookFunction for native symbols + MSHookMessageEx for ObjC getters",
        gInstalled ? @"YES" : @"NO",
        (unsigned long)gRecordCount,
        (unsigned long)gFunctionHookCount,
        (unsigned long)gScannedClasses,
        (unsigned long)FBGRGateAllOverrideSlotIds().count];
}
