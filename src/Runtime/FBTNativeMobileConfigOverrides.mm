#import "FBTNativeMobileConfigOverrides.h"
#import "../FBTPrefix.h"
#import <objc/runtime.h>
#import <pthread.h>
#import <dlfcn.h>
#import <memory>
#import <string>

// =====================================================================
// Native MobileConfig overrides, sem patch em __TEXT assinado.
//
// O v3 crashou porque MSHookFunction alterou código executável do
// FBSharedFramework. Esta camada faz o caminho correto: captura contextos
// por dispatch ObjC e chama APIs C++ exportadas normalmente via dlsym.
// =====================================================================

namespace mobileconfig {
class FBMobileConfigManager;
class FBMobileConfigOverridesTable;
}

typedef std::shared_ptr<mobileconfig::FBMobileConfigManager> (*FBTGetManagerFn)(id context);
typedef std::shared_ptr<mobileconfig::FBMobileConfigOverridesTable> (*FBTGetOrCreateTableFn)(mobileconfig::FBMobileConfigManager *manager, bool create);
typedef void (*FBTUpdateBoolFn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, bool value, bool persist);
typedef void (*FBTUpdateInt64Fn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, long long value, bool persist);
typedef void (*FBTUpdateDoubleFn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, double value, bool persist);
typedef void (*FBTUpdateStringFn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, const std::string &value, bool persist);
typedef void (*FBTRemoveFn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, bool persist);

static FBTGetManagerFn sGetManager = NULL;
static FBTGetOrCreateTableFn sGetOrCreateTable = NULL;
static FBTUpdateBoolFn sUpdateBool = NULL;
static FBTUpdateInt64Fn sUpdateInt64 = NULL;
static FBTUpdateDoubleFn sUpdateDouble = NULL;
static FBTUpdateStringFn sUpdateString = NULL;
static FBTRemoveFn sRemove = NULL;
static BOOL sSymbolsResolved = NO;
static BOOL sContextHooksInstalled = NO;

static NSHashTable *sContexts = nil; // weak objects
static NSMutableSet<NSString *> *sHookedMethods = nil;
static pthread_mutex_t sNativeLock = PTHREAD_MUTEX_INITIALIZER;

typedef id (*FBTObjectGetterOrig)(id, SEL);

typedef struct {
    SEL sel;
    IMP orig;
    CFStringRef key;
} FBTContextHookDescriptor;

static BOOL FBTResolveNativeSymbols(void) {
    if (sSymbolsResolved) {
        return sGetManager && sGetOrCreateTable && sUpdateBool && sUpdateInt64 && sUpdateDouble && sUpdateString && sRemove;
    }
    sSymbolsResolved = YES;

    sGetManager = (FBTGetManagerFn)dlsym(RTLD_DEFAULT, "__Z22getMobileConfigManagerPU32objcproto21FBMobileConfigContext11objc_object");
    sGetOrCreateTable = (FBTGetOrCreateTableFn)dlsym(RTLD_DEFAULT, "__ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb");
    sUpdateBool = (FBTUpdateBoolFn)dlsym(RTLD_DEFAULT, "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb");
    sUpdateInt64 = (FBTUpdateInt64Fn)dlsym(RTLD_DEFAULT, "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyxb");
    sUpdateDouble = (FBTUpdateDoubleFn)dlsym(RTLD_DEFAULT, "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEydb");
    sUpdateString = (FBTUpdateStringFn)dlsym(RTLD_DEFAULT, "__ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyRKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEEb");
    sRemove = (FBTRemoveFn)dlsym(RTLD_DEFAULT, "__ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb");

    BOOL ok = sGetManager && sGetOrCreateTable && sUpdateBool && sUpdateInt64 && sUpdateDouble && sUpdateString && sRemove;
    FBTLog(@"native MC symbols: %@", ok ? @"OK" : @"missing");
    return ok;
}

static BOOL FBTLooksLikeMobileConfigContext(id obj) {
    if (!obj) return NO;
    @try {
        Protocol *p = objc_getProtocol("FBMobileConfigContext");
        if (p && [obj conformsToProtocol:p]) return YES;
        NSString *cls = NSStringFromClass([obj class]);
        NSString *low = cls.lowercaseString;
        if ([low containsString:@"mobileconfig"] && [low containsString:@"context"]) return YES;
        if ([low containsString:@"mci"] && [low containsString:@"context"]) return YES;
    } @catch (__unused NSException *e) {
        return NO;
    }
    return NO;
}

void FBTNativeMobileConfigRegisterContext(id context) {
    if (!FBTLooksLikeMobileConfigContext(context)) return;
    pthread_mutex_lock(&sNativeLock);
    if (!sContexts) sContexts = [NSHashTable weakObjectsHashTable];
    [sContexts addObject:context];
    pthread_mutex_unlock(&sNativeLock);
}

NSUInteger FBTNativeMobileConfigContextCount(void) {
    pthread_mutex_lock(&sNativeLock);
    NSUInteger count = sContexts ? sContexts.allObjects.count : 0;
    pthread_mutex_unlock(&sNativeLock);
    return count;
}

NSString *FBTNativeMobileConfigStatus(void) {
    BOOL symbols = FBTResolveNativeSymbols();
    return [NSString stringWithFormat:@"native %@ · contexts %lu", symbols ? @"OK" : @"missing", (unsigned long)FBTNativeMobileConfigContextCount()];
}

static NSArray *FBTNativeContextsSnapshot(void) {
    pthread_mutex_lock(&sNativeLock);
    NSArray *items = sContexts ? [sContexts.allObjects copy] : @[];
    pthread_mutex_unlock(&sNativeLock);
    return items ?: @[];
}

static BOOL FBTApplyWithTable(id context, uint64_t key, NSString *type, id value, BOOL remove) {
    if (!context || !FBTResolveNativeSymbols()) return NO;
    try {
        std::shared_ptr<mobileconfig::FBMobileConfigManager> manager = sGetManager(context);
        if (!manager.get()) return NO;
        std::shared_ptr<mobileconfig::FBMobileConfigOverridesTable> table = sGetOrCreateTable(manager.get(), true);
        if (!table.get()) return NO;

        if (remove) {
            sRemove(table.get(), key, true);
            return YES;
        }

        if ([type isEqualToString:@"bool"]) {
            sUpdateBool(table.get(), key, [value boolValue] ? true : false, true);
            return YES;
        }
        if ([type isEqualToString:@"int64"]) {
            sUpdateInt64(table.get(), key, (long long)[value longLongValue], true);
            return YES;
        }
        if ([type isEqualToString:@"double"]) {
            sUpdateDouble(table.get(), key, [value doubleValue], true);
            return YES;
        }
        if ([type isEqualToString:@"string"]) {
            NSString *s = [value isKindOfClass:[NSString class]] ? value : [value description];
            std::string str(s ? [s UTF8String] : "");
            sUpdateString(table.get(), key, str, true);
            return YES;
        }
    } catch (...) {
        return NO;
    }
    return NO;
}

BOOL FBTNativeMobileConfigApplyOverride(uint64_t key, NSString *type, id value) {
    if (!type.length || !value) return NO;
    BOOL ok = NO;
    for (id ctx in FBTNativeContextsSnapshot()) {
        if (FBTApplyWithTable(ctx, key, type, value, NO)) ok = YES;
    }
    return ok;
}

BOOL FBTNativeMobileConfigRemoveOverride(uint64_t key) {
    BOOL ok = NO;
    for (id ctx in FBTNativeContextsSnapshot()) {
        if (FBTApplyWithTable(ctx, key, nil, nil, YES)) ok = YES;
    }
    return ok;
}

static NSString *FBTContextHookKey(NSString *className, NSString *selName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"-", className ?: @"", selName ?: @""];
}

static BOOL FBTClassCanHostContextGetter(NSString *className) {
    NSString *c = className.lowercaseString;
    return ([c containsString:@"mobileconfig"] || [c containsString:@"mci"] || [c containsString:@"mobileconfigcontext"]) &&
           ([c containsString:@"context"] || [c containsString:@"manager"]);
}

static BOOL FBTMethodLooksLikeContextGetter(Method m) {
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char ret[256] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (ret[0] != '@') return NO;
    NSString *retType = [NSString stringWithUTF8String:ret] ?: @"";
    NSString *sel = NSStringFromSelector(method_getName(m)).lowercaseString;
    NSString *lowRet = retType.lowercaseString;
    if ([lowRet containsString:@"fbmobileconfigcontext"]) return YES;
    if ([lowRet containsString:@"mobileconfig"] && [lowRet containsString:@"context"]) return YES;
    if ([sel containsString:@"context"] && ([sel containsString:@"mobileconfig"] || [sel containsString:@"user"] || [sel containsString:@"sessionless"])) return YES;
    if ([sel isEqualToString:@"context"] || [sel isEqualToString:@"mobileconfigcontext"]) return YES;
    return NO;
}

static void FBTHookContextMethodsForClass(Class cls, BOOL classMethods) {
    if (!cls) return;
    Class methodClass = classMethods ? object_getClass(cls) : cls;
    NSString *className = NSStringFromClass(cls);
    if (!FBTClassCanHostContextGetter(className)) return;

    unsigned int count = 0;
    Method *methods = class_copyMethodList(methodClass, &count);
    for (unsigned int i = 0; i < count; i++) {
        Method m = methods[i];
        if (!FBTMethodLooksLikeContextGetter(m)) continue;

        SEL sel = method_getName(m);
        NSString *selName = NSStringFromSelector(sel);
        NSString *key = FBTContextHookKey(className, selName, classMethods);

        pthread_mutex_lock(&sNativeLock);
        if (!sHookedMethods) sHookedMethods = [NSMutableSet set];
        if ([sHookedMethods containsObject:key]) { pthread_mutex_unlock(&sNativeLock); continue; }
        [sHookedMethods addObject:key];
        pthread_mutex_unlock(&sNativeLock);

        FBTContextHookDescriptor *desc = (FBTContextHookDescriptor *)calloc(1, sizeof(FBTContextHookDescriptor));
        if (!desc) continue;
        desc->sel = sel;
        desc->key = (CFStringRef)CFBridgingRetain(key);

        __block FBTContextHookDescriptor *captured = desc;
        IMP replacement = imp_implementationWithBlock(^id(id receiver) {
            id result = nil;
            if (captured->orig) {
                result = ((FBTObjectGetterOrig)captured->orig)(receiver, captured->sel);
            }
            FBTNativeMobileConfigRegisterContext(result);
            return result;
        });
        MSHookMessageEx(methodClass, sel, replacement, (IMP *)&desc->orig);
        FBTLog(@"native MC context hook: %@", key);
    }
    if (methods) free(methods);
}

void FBTInstallNativeMobileConfigContextCapture(void) {
    if (sContextHooksInstalled) return;
    sContextHooksInstalled = YES;
    FBTResolveNativeSymbols();

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) return;
    classCount = objc_getClassList(classes, classCount);
    for (int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        NSString *className = NSStringFromClass(cls);
        if (!FBTClassCanHostContextGetter(className)) continue;
        FBTHookContextMethodsForClass(cls, NO);
        FBTHookContextMethodsForClass(cls, YES);
    }
    free(classes);
}
