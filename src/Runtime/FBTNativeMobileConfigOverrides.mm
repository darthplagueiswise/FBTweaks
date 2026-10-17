#import "FBTNativeMobileConfigOverrides.h"
#import "FBTMobileConfigRuntime.h"
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

// Build 583 exports no getMobileConfigManager C++ helper. The native ObjC
// manager exposes these owning shared_ptr getters instead (ABI checked below).
@protocol FBTMCNativeManagerGetter <NSObject>
- (std::shared_ptr<mobileconfig::FBMobileConfigManager>)getCurrentManager;
- (std::shared_ptr<mobileconfig::FBMobileConfigManager>)configManager;
@end
typedef std::shared_ptr<mobileconfig::FBMobileConfigOverridesTable> (*FBTGetOrCreateTableFn)(mobileconfig::FBMobileConfigManager *manager, bool create);
typedef void (*FBTUpdateBoolFn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, bool value, bool persist);
typedef void (*FBTUpdateInt64Fn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, long long value, bool persist);
typedef void (*FBTUpdateDoubleFn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, double value, bool persist);
typedef void (*FBTUpdateStringFn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, const std::string &value, bool persist);
typedef void (*FBTRemoveFn)(mobileconfig::FBMobileConfigOverridesTable *table, uint64_t key, bool persist);
typedef void (*FBTSetSkipOverrideCheckEnabledFn)(BOOL enabled);

static FBTGetOrCreateTableFn sGetOrCreateTable = NULL;
static FBTUpdateBoolFn sUpdateBool = NULL;
static FBTUpdateInt64Fn sUpdateInt64 = NULL;
static FBTUpdateDoubleFn sUpdateDouble = NULL;
static FBTUpdateStringFn sUpdateString = NULL;
static FBTRemoveFn sRemove = NULL;
static FBTSetSkipOverrideCheckEnabledFn sSetSkipOverrideCheckEnabled = NULL;
static NSUInteger sLastMissingNativeSymbolMask = NSUIntegerMax;
// O processo carrega classes do Facebook em fases (incluindo RN/RarelyUsed).
// Revarremos quando a contagem de classes muda; os sets de hooks abaixo
// tornam cada instalação idempotente.
static int sLastScannedClassCount = 0;

static NSHashTable *sContexts = nil; // weak objects
static NSHashTable *sOverrideObjects = nil; // weak objects that implement native ObjC debug/override API
static NSMutableSet<NSString *> *sHookedMethods = nil;
static pthread_mutex_t sNativeLock = PTHREAD_MUTEX_INITIALIZER;

typedef id (*FBTObjectGetterOrig)(id, SEL);

typedef struct {
    SEL sel;
    IMP orig;
    CFStringRef key;
} FBTContextHookDescriptor;

static BOOL FBTResolveNativeSymbols(void) {
    // dlsym receives the ABI name, without Mach-O's additional underscore.
    // Retry unresolved exports: a failed lookup before a framework loads must
    // not disable this bridge for the rest of the process.
    if (!sGetOrCreateTable) sGetOrCreateTable = (FBTGetOrCreateTableFn)dlsym(RTLD_DEFAULT, "_ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb");
    if (!sUpdateBool) sUpdateBool = (FBTUpdateBoolFn)dlsym(RTLD_DEFAULT, "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb");
    if (!sUpdateInt64) sUpdateInt64 = (FBTUpdateInt64Fn)dlsym(RTLD_DEFAULT, "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyxb");
    if (!sUpdateDouble) sUpdateDouble = (FBTUpdateDoubleFn)dlsym(RTLD_DEFAULT, "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEydb");
    if (!sUpdateString) sUpdateString = (FBTUpdateStringFn)dlsym(RTLD_DEFAULT, "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyRKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEEb");
    if (!sRemove) sRemove = (FBTRemoveFn)dlsym(RTLD_DEFAULT, "_ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb");
    // Optional; it is absent from the supplied Facebook 583 IPA. Do not infer
    // availability from a historical config name or call an invented address.
    if (!sSetSkipOverrideCheckEnabled) sSetSkipOverrideCheckEnabled = (FBTSetSkipOverrideCheckEnabledFn)dlsym(RTLD_DEFAULT, "FBMobileConfigSetSkipOverrideCheckEnabled");

    BOOL ok = sGetOrCreateTable && sUpdateBool && sUpdateInt64 && sUpdateDouble && sUpdateString && sRemove;
    NSUInteger missingMask = (!sGetOrCreateTable ? 2u : 0u) |
        (!sUpdateBool ? 4u : 0u) | (!sUpdateInt64 ? 8u : 0u) | (!sUpdateDouble ? 16u : 0u) |
        (!sUpdateString ? 32u : 0u) | (!sRemove ? 64u : 0u);
    if (missingMask != sLastMissingNativeSymbolMask) {
        sLastMissingNativeSymbolMask = missingMask;
        NSMutableArray *missing = [NSMutableArray array];
        if (!sGetOrCreateTable) [missing addObject:@"getOrCreateOverridesTable"];
        if (!sUpdateBool) [missing addObject:@"updateOverrideForParam(bool)"];
        if (!sUpdateInt64) [missing addObject:@"updateOverrideForParam(int64)"];
        if (!sUpdateDouble) [missing addObject:@"updateOverrideForParam(double)"];
        if (!sUpdateString) [missing addObject:@"updateOverrideForParam(string)"];
        if (!sRemove) [missing addObject:@"removeOverrideForParam"];
        FBTLog(@"native MC C++ bridge: %@; missing=%@; optional skip API=%@",
               ok ? @"OK" : @"unavailable", missing, sSetSkipOverrideCheckEnabled ? @"available" : @"absent");
    }
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

static NSUInteger FBTNativeOverrideObjectCount(void) {
    pthread_mutex_lock(&sNativeLock);
    NSUInteger count = sOverrideObjects ? sOverrideObjects.allObjects.count : 0;
    pthread_mutex_unlock(&sNativeLock);
    return count;
}

static BOOL FBTOverrideObjectSetUsesScalarKey(id object) {
    if (!object) return NO;
    SEL sel = NSSelectorFromString(@"setOverrideForParam:andValue:");
    Method m = class_getInstanceMethod([object class], sel);
    if (!m) return NO;
    const char *types = method_getTypeEncoding(m);
    if (!types) return NO;
    NSString *t = [NSString stringWithUTF8String:types] ?: @"";
    return ([t containsString:@"Q16"] || [t containsString:@"{mc_"]);
}

static BOOL FBTOverrideObjectRemoveUsesScalarKey(id object) {
    if (!object) return NO;
    SEL sel = NSSelectorFromString(@"removeOverrideForParam:");
    Method m = class_getInstanceMethod([object class], sel);
    if (!m) return NO;
    const char *types = method_getTypeEncoding(m);
    if (!types) return NO;
    NSString *t = [NSString stringWithUTF8String:types] ?: @"";
    return ([t containsString:@"Q16"] || [t containsString:@"{mc_"]);
}

void FBTNativeMobileConfigRegisterOverrideObject(id object) {
    if (!object) return;
    @try {
        SEL setSel = NSSelectorFromString(@"setOverrideForParam:andValue:");
        SEL removeSel = NSSelectorFromString(@"removeOverrideForParam:");
        SEL pathSel = NSSelectorFromString(@"getOverridesTablePath");
        if (![object respondsToSelector:setSel] && ![object respondsToSelector:removeSel] && ![object respondsToSelector:pathSel]) return;
        pthread_mutex_lock(&sNativeLock);
        if (!sOverrideObjects) sOverrideObjects = [NSHashTable weakObjectsHashTable];
        [sOverrideObjects addObject:object];
        pthread_mutex_unlock(&sNativeLock);
    } @catch (__unused NSException *e) {
    }
}

static NSArray *FBTNativeOverrideObjectsSnapshot(void) {
    pthread_mutex_lock(&sNativeLock);
    NSArray *items = sOverrideObjects ? [sOverrideObjects.allObjects copy] : @[];
    pthread_mutex_unlock(&sNativeLock);
    return items ?: @[];
}

static NSArray<NSString *> *FBTNativeMobileConfigGroupCandidates(void) {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";
    NSMutableOrderedSet<NSString *> *groups = [NSMutableOrderedSet orderedSet];
    if ([bundleID.lowercaseString isEqualToString:@"com.facebook.ota"]) {
        [groups addObject:@"group.facebook.ota"];
        [groups addObject:@"group.com.facebook.ota"];
    } else if ([bundleID.lowercaseString isEqualToString:@"com.facebook.facebook"]) {
        [groups addObject:@"group.com.facebook.Facebook"];
        [groups addObject:@"group.facebook.Facebook"];
    }
    if (bundleID.length) [groups addObject:[@"group." stringByAppendingString:bundleID]];
    if ([bundleID hasPrefix:@"com."] && bundleID.length > 4) {
        [groups addObject:[@"group." stringByAppendingString:[bundleID substringFromIndex:4]]];
    }
    [groups addObject:@"group.com.facebook.Facebook"];
    [groups addObject:@"group.facebook.ota"];
    [groups addObject:@"group.com.facebook.ota"];
    [groups addObject:@"group.com.facebook.dogfood.internal"];
    [groups addObject:@"group.com.facebook.family"];
    return groups.array;
}

NSString *FBTNativeMobileConfigOverridesFilePath(void) {
    SEL pathSel = NSSelectorFromString(@"getOverridesTablePath");
    for (id obj in FBTNativeOverrideObjectsSnapshot()) {
        if (![obj respondsToSelector:pathSel]) continue;
        @try {
            NSString *(*msg)(id, SEL) = (NSString *(*)(id, SEL))objc_msgSend;
            id path = msg(obj, pathSel);
            if ([path isKindOfClass:[NSString class]] && [path length]) return path;
        } @catch (__unused NSException *e) {
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";
    NSString *fallbackPath = nil;
    for (NSString *group in FBTNativeMobileConfigGroupCandidates()) {
        NSURL *url = [fm containerURLForSecurityApplicationGroupIdentifier:group];
        if (!url.path.length) continue;

        NSMutableArray<NSString *> *candidates = [NSMutableArray array];
        // Keep a pre-existing file in its actual location. Some builds use
        // AppGroup/Documents/mobileconfig; others export mobileconfig directly
        // at the shared-container root.
        [candidates addObject:[[url.path stringByAppendingPathComponent:@"Documents/mobileconfig"] stringByAppendingPathComponent:@"mc_overrides.json"]];
        [candidates addObject:[[url.path stringByAppendingPathComponent:@"mobileconfig"] stringByAppendingPathComponent:@"mc_overrides.json"]];
        [candidates addObject:[[url.path stringByAppendingPathComponent:@"AppData/Documents/mobileconfig"] stringByAppendingPathComponent:@"mc_overrides.json"]];
        for (NSString *candidate in candidates) {
            if ([fm fileExistsAtPath:candidate]) return candidate;
        }

        // With no existing file, create the path for the suite inferred from
        // the active bundle, rather than taking the first unrelated group.
        NSString *preferredRelative = [bundleID.lowercaseString isEqualToString:@"com.facebook.ota"]
            ? @"Documents/mobileconfig/mc_overrides.json"
            : @"mobileconfig/mc_overrides.json";
        if (!fallbackPath) fallbackPath = [url.path stringByAppendingPathComponent:preferredRelative];
    }
    return fallbackPath;
}


static void FBTSetSkipOverrideCheckIfAvailable(BOOL enabled) {
    FBTResolveNativeSymbols();
    if (!sSetSkipOverrideCheckEnabled) return;
    @try {
        sSetSkipOverrideCheckEnabled(enabled);
    } @catch (__unused NSException *e) {
    }
}

BOOL FBTNativeMobileConfigEnsureOverridesFile(void) {
    FBTSetSkipOverrideCheckIfAvailable(YES);
    NSString *path = FBTNativeMobileConfigOverridesFilePath();
    if (!path.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (dir.length) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    if (![fm fileExistsAtPath:path]) {
        NSData *empty = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
        return [fm createFileAtPath:path contents:empty attributes:nil];
    }
    return YES;
}

NSString *FBTNativeMobileConfigStatus(void) {
    BOOL symbols = FBTResolveNativeSymbols();
    NSString *path = FBTNativeMobileConfigOverridesFilePath();
    BOOL fileExists = path.length ? [[NSFileManager defaultManager] fileExistsAtPath:path] : NO;
    return [NSString stringWithFormat:@"native %@ · skip %@ · contexts %lu · objc %lu · file %@", symbols ? @"OK" : @"missing", sSetSkipOverrideCheckEnabled ? @"OK" : @"missing", (unsigned long)FBTNativeMobileConfigContextCount(), (unsigned long)FBTNativeOverrideObjectCount(), path.length ? (fileExists ? @"exists" : @"missing") : @"unknown"];
}


static NSArray *FBTNativeContextsSnapshot(void) {
    pthread_mutex_lock(&sNativeLock);
    NSArray *items = sContexts ? [sContexts.allObjects copy] : @[];
    pthread_mutex_unlock(&sNativeLock);
    return items ?: @[];
}

static BOOL FBTApplyWithObjCOverrideObject(id object, uint64_t key, NSString *type, id value, BOOL remove) {
    if (!object) return NO;
    @try {
        if (remove) {
            SEL sel = NSSelectorFromString(@"removeOverrideForParam:");
            if (![object respondsToSelector:sel] || !FBTOverrideObjectRemoveUsesScalarKey(object)) return NO;
            void (*msg)(id, SEL, uint64_t) = (void (*)(id, SEL, uint64_t))objc_msgSend;
            msg(object, sel, key);
            FBTNativeMobileConfigEnsureOverridesFile();
            return YES;
        }

        SEL sel = NSSelectorFromString(@"setOverrideForParam:andValue:");
        if (![object respondsToSelector:sel] || !FBTOverrideObjectSetUsesScalarKey(object)) return NO;
        id boxed = value;
        if ([type isEqualToString:@"bool"]) boxed = @([value boolValue]);
        else if ([type isEqualToString:@"int64"]) boxed = @([value longLongValue]);
        else if ([type isEqualToString:@"double"]) boxed = @([value doubleValue]);
        else if ([type isEqualToString:@"string"]) boxed = [value isKindOfClass:[NSString class]] ? value : [value description];
        void (*msg)(id, SEL, uint64_t, id) = (void (*)(id, SEL, uint64_t, id))objc_msgSend;
        msg(object, sel, key, boxed);
        FBTNativeMobileConfigEnsureOverridesFile();
        return YES;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static BOOL FBTApplyWithTable(id context, uint64_t key, NSString *type, id value, BOOL remove) {
    if (!context || !FBTResolveNativeSymbols()) return NO;
    try {
        std::shared_ptr<mobileconfig::FBMobileConfigManager> manager;
        const char *expected = "{shared_ptr<mobileconfig::FBMobileConfigManager>=^{FBMobileConfigManager}^{__shared_weak_count}}16@0:8";
        for (NSString *selectorName in @[@"getCurrentManager", @"configManager"]) {
            SEL selector = NSSelectorFromString(selectorName);
            Method method = class_getInstanceMethod([context class], selector);
            if (!method || strcmp(method_getTypeEncoding(method), expected) != 0) continue;
            id<FBTMCNativeManagerGetter> owner = context;
            manager = [selectorName isEqualToString:@"getCurrentManager"]
                ? [owner getCurrentManager] : [owner configManager];
            if (manager.get()) break;
        }
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
    FBTSetSkipOverrideCheckIfAvailable(YES);
    FBTNativeMobileConfigEnsureOverridesFile();
    BOOL ok = NO;
    for (id obj in FBTNativeOverrideObjectsSnapshot()) {
        if (FBTApplyWithObjCOverrideObject(obj, key, type, value, NO)) ok = YES;
    }
    for (id ctx in FBTNativeContextsSnapshot()) {
        if (FBTApplyWithTable(ctx, key, type, value, NO)) ok = YES;
    }
    return ok;
}

BOOL FBTNativeMobileConfigRemoveOverride(uint64_t key) {
    FBTSetSkipOverrideCheckIfAvailable(YES);
    BOOL ok = NO;
    for (id obj in FBTNativeOverrideObjectsSnapshot()) {
        if (FBTApplyWithObjCOverrideObject(obj, key, nil, nil, YES)) ok = YES;
    }
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
            FBTNativeMobileConfigRegisterOverrideObject(receiver);
            FBTNativeMobileConfigRegisterContext(result);
            FBTNativeMobileConfigRegisterOverrideObject(result);
            return result;
        });
        MSHookMessageEx(methodClass, sel, replacement, (IMP *)&desc->orig);
        FBTLog(@"native MC context hook: %@", key);
    }
    if (methods) free(methods);
}


// ---------------------------------------------------------------------
// ObjC reader hooks for MobileConfig context managers.
// This is the safe replacement for the failed direct C export hook:
// dispatch ObjC is hookable via MSHookMessageEx without dirtying signed
// executable pages, and it catches the native framework/user-session
// readers that the Dogfood menu itself uses.
// ---------------------------------------------------------------------
typedef BOOL    (*FBTBool3Orig)(id, SEL, uint64_t, void *);
typedef BOOL    (*FBTBool4Orig)(id, SEL, uint64_t, void *, BOOL);
typedef int64_t (*FBTInt3Orig)(id, SEL, uint64_t, void *);
typedef int64_t (*FBTInt4Orig)(id, SEL, uint64_t, void *, int64_t);
typedef double  (*FBTDouble3Orig)(id, SEL, uint64_t, void *);
typedef double  (*FBTDouble4Orig)(id, SEL, uint64_t, void *, double);
typedef id      (*FBTString3Orig)(id, SEL, uint64_t, void *);
typedef id      (*FBTString4Orig)(id, SEL, uint64_t, void *, id);
typedef id      (*FBTObject0Orig)(id, SEL);
typedef id      (*FBTInitMappingOrig)(id, SEL, id, id);

typedef struct {
    SEL sel;
    IMP orig;
    CFStringRef key;
} FBTObjCReaderHookDescriptor;

static NSMutableSet<NSString *> *sObjCReaderHooks = nil;

static BOOL FBTOvBool(uint64_t key, BOOL *outForced) {
    NSDictionary *ov = FBTMobileConfigOverrideForKey(key);
    if (![ov isKindOfClass:[NSDictionary class]] || ![ov[@"t"] isEqualToString:@"bool"]) return NO;
    BOOL forced = [ov[@"v"] boolValue];
    if (outForced) *outForced = forced;
    return YES;
}

static BOOL FBTOvInt64(uint64_t key, int64_t *outForced) {
    NSDictionary *ov = FBTMobileConfigOverrideForKey(key);
    if (![ov isKindOfClass:[NSDictionary class]] || ![ov[@"t"] isEqualToString:@"int64"]) return NO;
    int64_t forced = (int64_t)[ov[@"v"] longLongValue];
    if (outForced) *outForced = forced;
    return YES;
}

static BOOL FBTOvDouble(uint64_t key, double *outForced) {
    NSDictionary *ov = FBTMobileConfigOverrideForKey(key);
    if (![ov isKindOfClass:[NSDictionary class]] || ![ov[@"t"] isEqualToString:@"double"]) return NO;
    double forced = [ov[@"v"] doubleValue];
    if (outForced) *outForced = forced;
    return YES;
}

static BOOL FBTOvString(uint64_t key, id *outForced) {
    NSDictionary *ov = FBTMobileConfigOverrideForKey(key);
    if (![ov isKindOfClass:[NSDictionary class]] || ![ov[@"t"] isEqualToString:@"string"]) return NO;
    id forced = [ov[@"v"] isKindOfClass:[NSString class]] ? ov[@"v"] : [ov[@"v"] description];
    if (outForced) *outForced = forced ?: @"";
    return YES;
}

static NSString *FBTHookKeyForClassSel(Class cls, SEL sel, NSString *suffix) {
    return [NSString stringWithFormat:@"%@#%@#%@", NSStringFromClass(cls) ?: @"?", NSStringFromSelector(sel) ?: @"?", suffix ?: @""];
}

static BOOL FBTMarkHookInstalled(Class cls, SEL sel, NSString *suffix) {
    NSString *key = FBTHookKeyForClassSel(cls, sel, suffix);
    pthread_mutex_lock(&sNativeLock);
    if (!sObjCReaderHooks) sObjCReaderHooks = [NSMutableSet set];
    BOOL exists = [sObjCReaderHooks containsObject:key];
    if (!exists) [sObjCReaderHooks addObject:key];
    pthread_mutex_unlock(&sNativeLock);
    return !exists;
}

static void FBTHookBool3(Class cls, SEL sel) {
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"b3")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t key, void *options) {
        FBTNativeMobileConfigRegisterContext(receiver);
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        BOOL original = captured->orig ? ((FBTBool3Orig)captured->orig)(receiver, captured->sel, key, options) : NO;
        BOOL forced = NO;
        if (FBTOvBool(key, &forced)) {
            FBTMobileConfigRecordAccess(key, @"bool", @(original), @(forced), YES);
            return forced;
        }
        FBTMobileConfigRecordAccess(key, @"bool", @(original), @(original), NO);
        return original;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookBool4(Class cls, SEL sel) {
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"b4")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t key, void *options, BOOL defaultValue) {
        FBTNativeMobileConfigRegisterContext(receiver);
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        BOOL original = captured->orig ? ((FBTBool4Orig)captured->orig)(receiver, captured->sel, key, options, defaultValue) : defaultValue;
        BOOL forced = NO;
        if (FBTOvBool(key, &forced)) {
            FBTMobileConfigRecordAccess(key, @"bool", @(defaultValue), @(forced), YES);
            return forced;
        }
        FBTMobileConfigRecordAccess(key, @"bool", @(defaultValue), @(original), NO);
        return original;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookInt3(Class cls, SEL sel) {
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"i3")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^int64_t(id receiver, uint64_t key, void *options) {
        FBTNativeMobileConfigRegisterContext(receiver);
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        int64_t original = captured->orig ? ((FBTInt3Orig)captured->orig)(receiver, captured->sel, key, options) : 0;
        int64_t forced = 0;
        if (FBTOvInt64(key, &forced)) {
            FBTMobileConfigRecordAccess(key, @"int64", @(original), @(forced), YES);
            return forced;
        }
        FBTMobileConfigRecordAccess(key, @"int64", @(original), @(original), NO);
        return original;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookInt4(Class cls, SEL sel) {
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"i4")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^int64_t(id receiver, uint64_t key, void *options, int64_t defaultValue) {
        FBTNativeMobileConfigRegisterContext(receiver);
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        int64_t original = captured->orig ? ((FBTInt4Orig)captured->orig)(receiver, captured->sel, key, options, defaultValue) : defaultValue;
        int64_t forced = 0;
        if (FBTOvInt64(key, &forced)) {
            FBTMobileConfigRecordAccess(key, @"int64", @(defaultValue), @(forced), YES);
            return forced;
        }
        FBTMobileConfigRecordAccess(key, @"int64", @(defaultValue), @(original), NO);
        return original;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookDouble3(Class cls, SEL sel) {
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"d3")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^double(id receiver, uint64_t key, void *options) {
        FBTNativeMobileConfigRegisterContext(receiver);
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        double original = captured->orig ? ((FBTDouble3Orig)captured->orig)(receiver, captured->sel, key, options) : 0.0;
        double forced = 0.0;
        if (FBTOvDouble(key, &forced)) {
            FBTMobileConfigRecordAccess(key, @"double", @(original), @(forced), YES);
            return forced;
        }
        FBTMobileConfigRecordAccess(key, @"double", @(original), @(original), NO);
        return original;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookDouble4(Class cls, SEL sel) {
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"d4")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^double(id receiver, uint64_t key, void *options, double defaultValue) {
        FBTNativeMobileConfigRegisterContext(receiver);
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        double original = captured->orig ? ((FBTDouble4Orig)captured->orig)(receiver, captured->sel, key, options, defaultValue) : defaultValue;
        double forced = 0.0;
        if (FBTOvDouble(key, &forced)) {
            FBTMobileConfigRecordAccess(key, @"double", @(defaultValue), @(forced), YES);
            return forced;
        }
        FBTMobileConfigRecordAccess(key, @"double", @(defaultValue), @(original), NO);
        return original;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookString3(Class cls, SEL sel) {
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"s3")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^id(id receiver, uint64_t key, void *options) {
        FBTNativeMobileConfigRegisterContext(receiver);
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        id original = captured->orig ? ((FBTString3Orig)captured->orig)(receiver, captured->sel, key, options) : nil;
        id forced = nil;
        if (FBTOvString(key, &forced)) {
            FBTMobileConfigRecordAccess(key, @"string", original, forced, YES);
            return forced;
        }
        FBTMobileConfigRecordAccess(key, @"string", original, original, NO);
        return original;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookString4(Class cls, SEL sel) {
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"s4")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^id(id receiver, uint64_t key, void *options, id defaultValue) {
        FBTNativeMobileConfigRegisterContext(receiver);
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        id original = captured->orig ? ((FBTString4Orig)captured->orig)(receiver, captured->sel, key, options, defaultValue) : defaultValue;
        id forced = nil;
        if (FBTOvString(key, &forced)) {
            FBTMobileConfigRecordAccess(key, @"string", defaultValue, forced, YES);
            return forced;
        }
        FBTMobileConfigRecordAccess(key, @"string", defaultValue, original, NO);
        return original;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookOverridesPath(Class cls) {
    SEL sel = NSSelectorFromString(@"getOverridesTablePath");
    if (!cls || !class_getInstanceMethod(cls, sel) || !FBTMarkHookInstalled(cls, sel, @"path")) return;
    FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
    desc->sel = sel;
    __block FBTObjCReaderHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^id(id receiver) {
        FBTNativeMobileConfigRegisterOverrideObject(receiver);
        id path = captured->orig ? ((FBTObject0Orig)captured->orig)(receiver, captured->sel) : nil;
        return path;
    });
    MSHookMessageEx(cls, sel, replacement, (IMP *)&desc->orig);
}

static void FBTHookNativeSetRemove(Class cls) {
    if (!cls) return;
    SEL setSel = NSSelectorFromString(@"setOverrideForParam:andValue:");
    Method setMethod = class_getInstanceMethod(cls, setSel);
    const char *setTypes = setMethod ? method_getTypeEncoding(setMethod) : NULL;
    NSString *setTypeString = setTypes ? [NSString stringWithUTF8String:setTypes] : @"";
    BOOL scalarSet = ([setTypeString containsString:@"Q16"] || [setTypeString containsString:@"{mc_"]);
    if (setMethod && scalarSet && FBTMarkHookInstalled(cls, setSel, @"set")) {
        FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
        desc->sel = setSel;
        __block FBTObjCReaderHookDescriptor *captured = desc;
        IMP replacement = imp_implementationWithBlock(^void(id receiver, uint64_t key, id value) {
            FBTNativeMobileConfigRegisterOverrideObject(receiver);
            if (captured->orig) ((void (*)(id, SEL, uint64_t, id))captured->orig)(receiver, captured->sel, key, value);
            FBTNativeMobileConfigEnsureOverridesFile();
        });
        MSHookMessageEx(cls, setSel, replacement, (IMP *)&desc->orig);
    }
    SEL removeSel = NSSelectorFromString(@"removeOverrideForParam:");
    Method removeMethod = class_getInstanceMethod(cls, removeSel);
    const char *removeTypes = removeMethod ? method_getTypeEncoding(removeMethod) : NULL;
    NSString *removeTypeString = removeTypes ? [NSString stringWithUTF8String:removeTypes] : @"";
    BOOL scalarRemove = ([removeTypeString containsString:@"Q16"] || [removeTypeString containsString:@"{mc_"]);
    if (removeMethod && scalarRemove && FBTMarkHookInstalled(cls, removeSel, @"remove")) {
        FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
        desc->sel = removeSel;
        __block FBTObjCReaderHookDescriptor *captured = desc;
        IMP replacement = imp_implementationWithBlock(^void(id receiver, uint64_t key) {
            FBTNativeMobileConfigRegisterOverrideObject(receiver);
            if (captured->orig) ((void (*)(id, SEL, uint64_t))captured->orig)(receiver, captured->sel, key);
            FBTNativeMobileConfigEnsureOverridesFile();
        });
        MSHookMessageEx(cls, removeSel, replacement, (IMP *)&desc->orig);
    }
}

static void FBTHookFBTContextManagerBridge(void) {
    Class cls = objc_getClass("FBMobileConfigFBTContextManager");
    if (!cls) return;
    SEL initSel = NSSelectorFromString(@"initWithFbtToMCIdMapping:mobileconfig:");
    if (class_getInstanceMethod(cls, initSel) && FBTMarkHookInstalled(cls, initSel, @"initDebugAPI")) {
        FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
        desc->sel = initSel;
        __block FBTObjCReaderHookDescriptor *captured = desc;
        IMP replacement = imp_implementationWithBlock(^id(id receiver, id mapping, id mobileconfig) {
            FBTNativeMobileConfigRegisterOverrideObject(mobileconfig);
            id obj = captured->orig ? ((FBTInitMappingOrig)captured->orig)(receiver, captured->sel, mapping, mobileconfig) : receiver;
            FBTNativeMobileConfigRegisterOverrideObject(obj);
            return obj;
        });
        MSHookMessageEx(cls, initSel, replacement, (IMP *)&desc->orig);
    }
    SEL getterSel = NSSelectorFromString(@"mobileconfig");
    if (class_getInstanceMethod(cls, getterSel) && FBTMarkHookInstalled(cls, getterSel, @"debugAPIGetter")) {
        FBTObjCReaderHookDescriptor *desc = (FBTObjCReaderHookDescriptor *)calloc(1, sizeof(FBTObjCReaderHookDescriptor));
        desc->sel = getterSel;
        __block FBTObjCReaderHookDescriptor *captured = desc;
        IMP replacement = imp_implementationWithBlock(^id(id receiver) {
            id obj = captured->orig ? ((FBTObject0Orig)captured->orig)(receiver, captured->sel) : nil;
            FBTNativeMobileConfigRegisterOverrideObject(obj);
            return obj;
        });
        MSHookMessageEx(cls, getterSel, replacement, (IMP *)&desc->orig);
    }
}

static void FBTHookMobileConfigReadersForClassName(const char *name, BOOL withDefaultAlso) {
    Class cls = objc_getClass(name);
    if (!cls) return;
    FBTHookBool3(cls, NSSelectorFromString(@"getBool:withOptions:"));
    FBTHookInt3(cls, NSSelectorFromString(@"getInt64:withOptions:"));
    FBTHookDouble3(cls, NSSelectorFromString(@"getDouble:withOptions:"));
    FBTHookString3(cls, NSSelectorFromString(@"getString:withOptions:"));
    if (withDefaultAlso) {
        FBTHookBool4(cls, NSSelectorFromString(@"getBool:withOptions:withDefault:"));
        FBTHookInt4(cls, NSSelectorFromString(@"getInt64:withOptions:withDefault:"));
        FBTHookDouble4(cls, NSSelectorFromString(@"getDouble:withOptions:withDefault:"));
        FBTHookString4(cls, NSSelectorFromString(@"getString:withOptions:withDefault:"));
    }
    FBTHookOverridesPath(cls);
    FBTHookNativeSetRemove(cls);
}

static void FBTInstallKnownObjCMobileConfigHooks(void) {
    FBTHookFBTContextManagerBridge();
    FBTHookMobileConfigReadersForClassName("FBMobileConfigStartupConfigs", YES);
    FBTHookMobileConfigReadersForClassName("FBMobileConfigStartupConfigsDeprecated", YES);
    FBTHookMobileConfigReadersForClassName("RCTMobileConfigNative", YES);
    FBTHookMobileConfigReadersForClassName("FBMobileConfigSessionlessContextManager", NO);
    FBTHookMobileConfigReadersForClassName("FBMobileConfigUserSessionContextManager", NO);
    FBTHookMobileConfigReadersForClassName("FBMobileConfigContextObjcImpl", YES);
    FBTHookMobileConfigReadersForClassName("FBMobileConfigContextManager", YES);
    FBTHookMobileConfigReadersForClassName("IGMobileConfigContextManager", YES);
    FBTHookMobileConfigReadersForClassName("IGMobileConfigSessionlessContextManager", NO);
    FBTHookMobileConfigReadersForClassName("IGMobileConfigUserSessionContextManager", NO);
    FBTHookMobileConfigReadersForClassName("FBMobileConfigEmptyImpl", YES);
}

static BOOL FBTClassLooksLikeGenericMobileConfigReader(NSString *className) {
    NSString *c = className.lowercaseString ?: @"";
    if ([c containsString:@"mobileconfig"]) return YES;
    if ([c containsString:@"metaconfig"]) return YES;
    if ([c containsString:@"rctmobileconfig"]) return YES;
    if ([c containsString:@"mci"] && [c containsString:@"config"]) return YES;
    return NO;
}

static void FBTInstallGenericObjCMobileConfigReaderHooks(Class cls) {
    if (!cls) return;
    NSString *className = NSStringFromClass(cls);
    if (!FBTClassLooksLikeGenericMobileConfigReader(className)) return;
    // O novo FBReactNativeProductsFramework usa RCTMobileConfigNative, e builds
    // recentes movem readers entre classes. Em vez de depender só de nomes
    // hardcoded, quando o usuário liga MobileConfig pós-launch instalamos nos
    // readers ObjC que existirem na classe. class_getInstanceMethod protege as
    // assinaturas ausentes; não há varredura no ctor.
    FBTHookBool3(cls, NSSelectorFromString(@"getBool:withOptions:"));
    FBTHookInt3(cls, NSSelectorFromString(@"getInt64:withOptions:"));
    FBTHookDouble3(cls, NSSelectorFromString(@"getDouble:withOptions:"));
    FBTHookString3(cls, NSSelectorFromString(@"getString:withOptions:"));
    FBTHookBool4(cls, NSSelectorFromString(@"getBool:withOptions:withDefault:"));
    FBTHookInt4(cls, NSSelectorFromString(@"getInt64:withOptions:withDefault:"));
    FBTHookDouble4(cls, NSSelectorFromString(@"getDouble:withOptions:withDefault:"));
    FBTHookString4(cls, NSSelectorFromString(@"getString:withOptions:withDefault:"));
    FBTHookOverridesPath(cls);
    FBTHookNativeSetRemove(cls);
}

void FBTInstallNativeMobileConfigContextCapture(void) {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    if (classCount == sLastScannedClassCount) return;
    FBTResolveNativeSymbols();
    FBTInstallKnownObjCMobileConfigHooks();
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) return;
    classCount = objc_getClassList(classes, classCount);
    for (int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        NSString *className = NSStringFromClass(cls);
        FBTInstallGenericObjCMobileConfigReaderHooks(cls);
        if (!FBTClassCanHostContextGetter(className)) continue;
        FBTHookContextMethodsForClass(cls, NO);
        FBTHookContextMethodsForClass(cls, YES);
    }
    free(classes);
    sLastScannedClassCount = classCount;
    FBTLog(@"native MC late-class scan: %d classes", classCount);
}
