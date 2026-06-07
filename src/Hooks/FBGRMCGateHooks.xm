#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRLog.h"
#import "../../modules/fishhook/fishhook.h"
#import <string.h>

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

typedef struct {
    Class cls;
    SEL sel;
    FBGRMCSigKind kind;
    BOOL classMethod;
    IMP orig;
} FBGRMCRecord;

#define FBGR_MC_MAX_RECORDS 512
static FBGRMCRecord gRecords[FBGR_MC_MAX_RECORDS];
static NSUInteger gRecordCount = 0;
static BOOL gInstalled = NO;
static BOOL gInstalling = NO;
static NSUInteger gScannedClasses = 0;
static NSUInteger gFishhookCount = 0;
static __thread BOOL gGuard = NO;

static BOOL (*orig_mc_getBoolDefault)(uint64_t slot) = NULL;
static BOOL (*orig_iglu_getBool)(void *self, const char *key) = NULL;

static FBGRMCRecord *FBGRMCFindRecord(Class cls, SEL sel, FBGRMCSigKind kind) {
    for (NSUInteger i = 0; i < gRecordCount; i++) {
        if (gRecords[i].cls == cls && gRecords[i].sel == sel && gRecords[i].kind == kind) return &gRecords[i];
    }
    for (NSUInteger i = 0; i < gRecordCount; i++) {
        if (gRecords[i].sel == sel && gRecords[i].kind == kind) return &gRecords[i];
    }
    return NULL;
}

static BOOL FBGRMCOverrideForSlot(uint64_t slot, BOOL fallback) {
    if (FBGRGateIsSet(slot)) return FBGRGateGet(slot);
    return fallback;
}

static BOOL FBGRMCOverrideForKey(id keyObject, BOOL fallback) {
    if ([keyObject isKindOfClass:NSNumber.class]) return FBGRMCOverrideForSlot([(NSNumber *)keyObject unsignedLongLongValue], fallback);
    if (![keyObject isKindOfClass:NSString.class]) return fallback;
    BOOL found = NO;
    uint64_t slot = [[FBGRMCCatalog shared] slotIdForKey:(NSString *)keyObject found:&found];
    return found ? FBGRMCOverrideForSlot(slot, fallback) : fallback;
}

static BOOL h_key1(id self, SEL _cmd, id key) {
    FBGRMCRecord *r = FBGRMCFindRecord(object_getClass(self), _cmd, FBGRMCSigKey1);
    Key1IMP orig = r ? (Key1IMP)r->orig : NULL;
    BOOL original = NO;
    if (!gGuard && orig) { gGuard = YES; original = orig(self, _cmd, key); gGuard = NO; }
    return FBGRMCOverrideForKey(key, original);
}

static BOOL h_keyDefault(id self, SEL _cmd, id key, BOOL def) {
    FBGRMCRecord *r = FBGRMCFindRecord(object_getClass(self), _cmd, FBGRMCSigKeyDefault);
    KeyDefaultIMP orig = r ? (KeyDefaultIMP)r->orig : NULL;
    BOOL original = def;
    if (!gGuard && orig) { gGuard = YES; original = orig(self, _cmd, key, def); gGuard = NO; }
    return FBGRMCOverrideForKey(key, original);
}

static BOOL h_param1(id self, SEL _cmd, mc_bool_param_t p) {
    FBGRMCRecord *r = FBGRMCFindRecord(object_getClass(self), _cmd, FBGRMCSigParam1);
    Param1IMP orig = r ? (Param1IMP)r->orig : NULL;
    BOOL original = NO;
    if (!gGuard && orig) { gGuard = YES; original = orig(self, _cmd, p); gGuard = NO; }
    return FBGRMCOverrideForSlot(p.value, original);
}

static BOOL h_paramDefault(id self, SEL _cmd, mc_bool_param_t p, BOOL def) {
    FBGRMCRecord *r = FBGRMCFindRecord(object_getClass(self), _cmd, FBGRMCSigParamDefault);
    ParamDefaultIMP orig = r ? (ParamDefaultIMP)r->orig : NULL;
    BOOL original = def;
    if (!gGuard && orig) { gGuard = YES; original = orig(self, _cmd, p, def); gGuard = NO; }
    return FBGRMCOverrideForSlot(p.value, original);
}

static BOOL h_paramOptions(id self, SEL _cmd, mc_bool_param_t p, id opts) {
    FBGRMCRecord *r = FBGRMCFindRecord(object_getClass(self), _cmd, FBGRMCSigParamOptions);
    ParamOptionsIMP orig = r ? (ParamOptionsIMP)r->orig : NULL;
    BOOL original = NO;
    if (!gGuard && orig) { gGuard = YES; original = orig(self, _cmd, p, opts); gGuard = NO; }
    return FBGRMCOverrideForSlot(p.value, original);
}

static BOOL h_paramOptionsDefault(id self, SEL _cmd, mc_bool_param_t p, id opts, BOOL def) {
    FBGRMCRecord *r = FBGRMCFindRecord(object_getClass(self), _cmd, FBGRMCSigParamOptionsDefault);
    ParamOptionsDefaultIMP orig = r ? (ParamOptionsDefaultIMP)r->orig : NULL;
    BOOL original = def;
    if (!gGuard && orig) { gGuard = YES; original = orig(self, _cmd, p, opts, def); gGuard = NO; }
    return FBGRMCOverrideForSlot(p.value, original);
}

static BOOL h_mc_getBoolDefault(uint64_t slot) {
    BOOL original = orig_mc_getBoolDefault ? orig_mc_getBoolDefault(slot) : NO;
    return FBGRMCOverrideForSlot(slot, original);
}

static BOOL h_iglu_getBool(void *selfPtr, const char *key) {
    BOOL original = orig_iglu_getBool ? orig_iglu_getBool(selfPtr, key) : NO;
    if (!key) return original;
    NSString *s = [NSString stringWithUTF8String:key];
    return FBGRMCOverrideForKey(s, original);
}

static NSString *FBGRArgType(Method m, unsigned int idx) {
    char buf[256]; memset(buf, 0, sizeof(buf));
    method_getArgumentType(m, idx, buf, sizeof(buf));
    return [NSString stringWithUTF8String:buf] ?: @"";
}

static BOOL FBGRArgIsObject(Method m, unsigned int idx) {
    NSString *t = FBGRArgType(m, idx);
    return [t hasPrefix:@"@"] || [t hasPrefix:@"?"];
}

static FBGRMCSigKind FBGRKindForMethod(NSString *selName, Method m) {
    unsigned int argc = method_getNumberOfArguments(m);
    BOOL objFirst = argc > 2 ? FBGRArgIsObject(m, 2) : NO;

    if ([selName isEqualToString:@"getBool:"] || [selName isEqualToString:@"getBoolWithoutLogging:"] || [selName isEqualToString:@"boolValueForParamKey:"] || [selName isEqualToString:@"ig_boolForKey:"]) {
        if (argc == 3) return objFirst ? FBGRMCSigKey1 : FBGRMCSigParam1;
    }

    if ([selName isEqualToString:@"getBool:withDefault:"] || [selName isEqualToString:@"getBoolWithoutLogging:withDefault:"] || [selName isEqualToString:@"getBoolForParam:withDefault:"] || [selName isEqualToString:@"boolForParameter:withDefault:"] || [selName isEqualToString:@"ig_boolForKey:defaultValue:"]) {
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

static BOOL FBGRImageLooksRelevant(const char *imageName) {
    if (!imageName) return NO;
    NSString *img = [NSString stringWithUTF8String:imageName] ?: @"";
    return [img containsString:@"/Facebook.app/Facebook"] || [img containsString:@"/FBSharedFramework.framework/FBSharedFramework"];
}

static BOOL FBGRClassNameLooksRelevant(Class cls) {
    NSString *name = NSStringFromClass(cls);
    NSString *lower = name.lowercaseString;
    return [lower containsString:@"mobileconfig"] || [lower containsString:@"contextualconfig"] || [lower containsString:@"config"] || [lower containsString:@"gate"] || [lower containsString:@"gating"] || [lower containsString:@"experiment"];
}

static void FBGRHookMethod(Class cls, Method m, BOOL classMethod) {
    if (!cls || !m || gRecordCount >= FBGR_MC_MAX_RECORDS) return;
    SEL sel = method_getName(m);
    NSString *selName = NSStringFromSelector(sel);
    FBGRMCSigKind kind = FBGRKindForMethod(selName, m);
    if (!kind) return;

    Class hookClass = classMethod ? object_getClass(cls) : cls;
    if (FBGRMCFindRecord(hookClass, sel, kind)) return;

    IMP replacement = FBGRReplacementForKind(kind);
    if (!replacement) return;

    IMP orig = NULL;
    MSHookMessageEx(hookClass, sel, replacement, &orig);
    if (!orig) return;

    gRecords[gRecordCount++] = (FBGRMCRecord){ hookClass, sel, kind, classMethod, orig };
}

static void FBGRScanAndHookObjC(void) {
    int n = objc_getClassList(NULL, 0);
    if (n <= 0) return;
    Class *classes = (Class *)calloc((NSUInteger)n, sizeof(Class));
    n = objc_getClassList(classes, n);

    for (int i = 0; i < n; i++) {
        Class cls = classes[i];
        if (!FBGRImageLooksRelevant(class_getImageName(cls)) && !FBGRClassNameLooksRelevant(cls)) continue;
        gScannedClasses++;

        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int j = 0; j < count; j++) FBGRHookMethod(cls, methods[j], NO);
        if (methods) free(methods);

        count = 0;
        methods = class_copyMethodList(object_getClass(cls), &count);
        for (unsigned int j = 0; j < count; j++) FBGRHookMethod(cls, methods[j], YES);
        if (methods) free(methods);
    }
    free(classes);
}

static void FBGRInstallFishhooks(void) {
    struct rebinding rbs[] = {
        { "__ZN12mobileconfig14getBoolDefaultEy", (void *)h_mc_getBoolDefault, (void **)&orig_mc_getBoolDefault },
        { "__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc", (void *)h_iglu_getBool, (void **)&orig_iglu_getBool },
    };
    rebind_symbols(rbs, 2);
    gFishhookCount = (orig_mc_getBoolDefault ? 1 : 0) + (orig_iglu_getBool ? 1 : 0);
}

static void FBGRInstall(void) {
    if (gInstalled || gInstalling) return;
    gInstalling = YES;
    FBGRGateWarmCacheFromPrefs();
    [[FBGRMCCatalog shared] loadIfNeeded];
    FBGRInstallFishhooks();
    FBGRScanAndHookObjC();
    gInstalled = YES;
    gInstalling = NO;
    FBGRLogAppend([NSString stringWithFormat:@"MC hooks installed: objc=%lu fishhook=%lu scanned=%lu", (unsigned long)gRecordCount, (unsigned long)gFishhookCount, (unsigned long)gScannedClasses]);
}

extern "C" void FBGRMCGateHooksEnsureInstalled(void) { FBGRInstall(); }
extern "C" void FBGRMCGateHooksApplyPersistedOverrides(void) { FBGRGateWarmCacheFromPrefs(); FBGRInstall(); }
extern "C" void FBGRMCGateCacheRefresh(void) { FBGRGateWarmCacheFromPrefs(); }

extern "C" NSString *FBGRMCGateHooksDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\nobjc hooks=%lu\nfishhooks=%lu\nscanned classes=%lu\noverrides=%lu\nselectors: key/string + param/slot variants",
        gInstalled ? @"YES" : @"NO",
        (unsigned long)gRecordCount,
        (unsigned long)gFishhookCount,
        (unsigned long)gScannedClasses,
        (unsigned long)FBGRGateAllOverrideSlotIds().count];
}
