#import "FBTRuntimeBoolBrowser.h"
#import "FBTNativeTrace.h"
#import "../FBTDefaults.h"
#import "../FBTPrefix.h"
#import <objc/runtime.h>
#import <pthread.h>
#import <dlfcn.h>
#import <string.h>

// Runtime browser arbitrário: exceção controlada ao padrão Logos.
// Varredura só on-demand na tela; no launch reinstala apenas hooks persistidos.

typedef BOOL (*FBTBoolOrigImp)(id, SEL);

typedef struct {
    SEL sel;
    IMP orig;
    CFStringRef key;
    int forceMode;  // -1 original, 0 OFF, 1 ON; atomic accesses
    int observedOriginal; // -1 until original really executed
    int observedEffective; // -1 until any invocation
    unsigned long long invocationCount;
} FBTBoolHookDescriptor;

static NSMutableDictionary<NSString *, NSValue *> *sInstalled; // key -> descriptor ptr
static NSDictionary *sOverrides;                                // key -> {force,class,selector,classMethod}
static NSMutableDictionary<NSString *, NSDictionary *> *sInstallFailures; // key -> state/reason
static BOOL sBoolBrowserEnabled = NO;
static pthread_mutex_t sBoolLock = PTHREAD_MUTEX_INITIALIZER;

static NSString *FBTImageKindForPath(NSString *path) {
    NSString *p = path ?: @"";
    NSString *last = p.lastPathComponent ?: @"";
    if ([last isEqualToString:@"Facebook"] || [last isEqualToString:@"Instagram"]) return @"main-exec";
    if ([last containsString:@"FBSharedFramework"]) return @"FBSharedFramework";
    if ([last containsString:@"FBReactNativeProductsFramework"]) return @"FBReactNativeProductsFramework";
    if ([last containsString:@"FBDogFoodUI"]) return @"FBDogFoodUI";
    if ([p containsString:@"/Frameworks/"]) return @"framework";
    if ([p containsString:@"/System/Library/"]) return @"system";
    return last.length ? last : @"unknown";
}

static BOOL FBTQueryMatchesHaystack(NSString *query, NSString *haystack) {
    NSString *q = [query.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (!q.length) return YES;
    NSString *h = haystack.lowercaseString ?: @"";
    NSArray<NSString *> *tokens = [q componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *token in tokens) {
        if (!token.length) continue;
        if ([h rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

static NSString *FBTImagePathForMethod(Method m) {
    if (!m) return @"";
    IMP imp = method_getImplementation(m);
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (imp && dladdr((const void *)imp, &info) && info.dli_fname) {
        return [NSString stringWithUTF8String:info.dli_fname] ?: @"";
    }
    return @"";
}

static NSString *FBTBoolKey(NSString *className, NSString *selectorName, BOOL isClassMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", isClassMethod ? @"+" : @"", className ?: @"", selectorName ?: @""];
}

static BOOL FBTBoolDecodeKey(NSString *key, NSString **className, NSString **selectorName, BOOL *isClassMethod) {
    if (![key isKindOfClass:[NSString class]] || !key.length) return NO;
    BOOL clsMethod = [key hasPrefix:@"+"];
    NSString *body = clsMethod ? [key substringFromIndex:1] : key;
    NSRange r = [body rangeOfString:@"#"];
    if (r.location == NSNotFound || r.location == 0 || NSMaxRange(r) >= body.length) return NO;
    if (className) *className = [body substringToIndex:r.location];
    if (selectorName) *selectorName = [body substringFromIndex:NSMaxRange(r)];
    if (isClassMethod) *isClassMethod = clsMethod;
    return YES;
}

static NSDictionary *FBTBoolOverrideForKey(NSString *key) {
    pthread_mutex_lock(&sBoolLock);
    NSDictionary *ov = sOverrides[key];
    NSDictionary *answer = [ov isKindOfClass:[NSDictionary class]] ? ov : nil;
    pthread_mutex_unlock(&sBoolLock);
    return answer;
}

static int FBTBoolMode(NSDictionary *override, BOOL enabled) {
    if (!enabled || ![override isKindOfClass:[NSDictionary class]]) return -1;
    id value = override[@"force"];
    return [value respondsToSelector:@selector(boolValue)] ? ([value boolValue] ? 1 : 0) : -1;
}

void FBTRuntimeBoolReloadPrefs(void) {
    BOOL enabled = [FBTDefaults boolForKey:FBTKeyRuntimeBoolBrowserEnabled];
    NSDictionary *snapshot = [[FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides] copy] ?: @{};
    pthread_mutex_lock(&sBoolLock);
    sBoolBrowserEnabled = enabled;
    sOverrides = snapshot;
    for (NSValue *v in sInstalled.allValues) {
        FBTBoolHookDescriptor *desc = [v pointerValue];
        if (!desc) continue;
        NSString *key = (__bridge NSString *)desc->key;
        __atomic_store_n(&desc->forceMode, FBTBoolMode(snapshot[key], enabled), __ATOMIC_RELEASE);
    }
    pthread_mutex_unlock(&sBoolLock);
}

NSDictionary *FBTRuntimeBoolOverridesSnapshot(void) {
    pthread_mutex_lock(&sBoolLock);
    NSDictionary *snapshot = sOverrides ?: @{};
    pthread_mutex_unlock(&sBoolLock);
    return snapshot;
}

NSNumber *FBTRuntimeBoolObservedOriginal(NSString *key) {
    if (!key.length) return nil;
    pthread_mutex_lock(&sBoolLock);
    FBTBoolHookDescriptor *desc = [sInstalled[key] pointerValue];
    pthread_mutex_unlock(&sBoolLock);
    if (!desc) return nil;
    int original = __atomic_load_n(&desc->observedOriginal,__ATOMIC_ACQUIRE);
    return original < 0 ? nil : @(original != 0);
}

BOOL FBTRuntimeBoolHookInstalledForKey(NSString *key) {
    if (!key.length) return NO;
    pthread_mutex_lock(&sBoolLock);
    BOOL installed = sInstalled[key] != nil;
    pthread_mutex_unlock(&sBoolLock);
    return installed;
}

// class_getInstanceMethod() also finds inherited methods. Only hook methods
// implemented on the selected class/metaclass, not its whole inheritance tree.
static BOOL FBTBoolClassImplementsSelector(Class hookClass, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(hookClass, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) { found = YES; break; }
    }
    if (methods) free(methods);
    return found;
}

static void FBTBoolRecordInstallIssue(NSString *key, NSString *state, NSString *reason) {
    if (!key.length) return;
    pthread_mutex_lock(&sBoolLock);
    if (!sInstallFailures) sInstallFailures = [NSMutableDictionary dictionary];
    sInstallFailures[key] = @{@"status": state ?: @"rejected", @"reason": reason ?: @"unknown"};
    pthread_mutex_unlock(&sBoolLock);
}
static BOOL FBTRuntimeBoolInstallOne(NSString *className, NSString *selectorName, BOOL isClassMethod) {
    if (!className.length || !selectorName.length) return NO;
    NSString *key = FBTBoolKey(className, selectorName, isClassMethod);
    // Known Logos/semantic hooks own these specific getters, even when their
    // feature toggle is OFF. Never add a competing runtime trampoline.
    static NSDictionary<NSString *, NSSet<NSString *> *> *knownOwners;
    static dispatch_once_t knownOnce;
    dispatch_once(&knownOnce, ^{
        knownOwners = @{
          @"FBUserPreferences": [NSSet setWithObject:@"isEmployee"],
          @"FBUser": [NSSet setWithObject:@"isEmployee"],
          @"FBBugReportConfiguration": [NSSet setWithObject:@"isEmployee"],
          @"FBProductTagCreationLogger": [NSSet setWithObject:@"isEmployee"],
          @"FBSnacksThreadOwnerMessengerContact": [NSSet setWithObject:@"isEmployee"],
          @"RCDMobileConfigParams": [NSSet setWithObject:@"isEmployee"],
          @"MBUISimpleParticipantModel": [NSSet setWithObject:@"isEmployee"],
          @"FBLoggedOutImageNetworkerConfiguration": [NSSet setWithObject:@"isViewerEmployee"],
          @"FBSessionImageNetworkerConfiguration": [NSSet setWithObject:@"isViewerEmployee"],
          @"FBBugReportInitialCoordinator": [NSSet setWithObject:@"triageToDogfoodingAssistantSession"],
          @"FBSnacksAdsDeliveryConfig": [NSSet setWithObject:@"enableDogfoodingView"],
          @"FBClientRageShakeBugReporterIssueComponentState": [NSSet setWithObject:@"triageToDogfoodingAssistantSession"],
          @"FBClientRageShakeBugReporterIssueModel": [NSSet setWithObject:@"triageToDogfoodingAssistantSession"],
          @"FFDBInternalSettingsWebViewController": [NSSet setWithObject:@"isInternLoggedIn"]
        };
    });
    if (!isClassMethod && [knownOwners[className] containsObject:selectorName]) {
        FBTLog(@"runtime BOOL skipped (known hook owns %@)",key);
        FBTBoolRecordInstallIssue(key, @"rejected", @"Selector controlado por outro hook conhecido");
        return NO;
    }

    pthread_mutex_lock(&sBoolLock);
    if (sInstalled[key]) { pthread_mutex_unlock(&sBoolLock); return YES; }
    pthread_mutex_unlock(&sBoolLock);

    Class cls = objc_getClass(className.UTF8String);
    if (!cls) {
        FBTBoolRecordInstallIssue(key, @"pending", @"Classe ainda não carregada pelo runtime");
        return NO;
    }
    Class hookClass = isClassMethod ? object_getClass(cls) : cls;
    SEL sel = NSSelectorFromString(selectorName);
    if (!FBTBoolClassImplementsSelector(hookClass, sel)) {
        FBTBoolRecordInstallIssue(key, @"rejected", @"Selector ausente nesta classe/metaclasse");
        return NO;
    }
    Method m = class_getInstanceMethod(hookClass, sel);
    if (!m) {
        FBTBoolRecordInstallIssue(key, @"rejected", @"Method não localizado");
        return NO;
    }
    if (method_getNumberOfArguments(m) != 2) {
        FBTBoolRecordInstallIssue(key, @"rejected", @"Método exige argumentos; ABI incompatível");
        return NO;
    }
    char ret[16] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (!(ret[0] == 'B' || ret[0] == 'c')) {
        FBTBoolRecordInstallIssue(key, @"rejected", @"Tipo de retorno não é BOOL/char");
        return NO;
    }
    const char *encoding = method_getTypeEncoding(m);
    if (!encoding || (strcmp(encoding,"B16@0:8") && strcmp(encoding,"c16@0:8"))) {
        FBTBoolRecordInstallIssue(key, @"rejected", @"Encoding ObjC não corresponde à ABI BOOL sem argumentos");
        return NO;
    }

    FBTBoolHookDescriptor *desc = calloc(1, sizeof(FBTBoolHookDescriptor));
    if (!desc) {
        FBTBoolRecordInstallIssue(key, @"rejected", @"Falha de alocação de descriptor");
        return NO;
    }
    desc->sel = sel;
    desc->key = (CFStringRef)CFBridgingRetain(key);
    desc->forceMode = FBTBoolMode(FBTBoolOverrideForKey(key), sBoolBrowserEnabled);
    desc->observedOriginal = -1;
    desc->observedEffective = -1;

    __block FBTBoolHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver) {
        unsigned long long count = __atomic_add_fetch(&captured->invocationCount, 1ULL, __ATOMIC_RELAXED);
        int mode = __atomic_load_n(&captured->forceMode, __ATOMIC_ACQUIRE);
        // No original call on a forced path: getters may have side effects.
        if (mode != -1) {
            __atomic_store_n(&captured->observedEffective, mode, __ATOMIC_RELAXED);
            if (FBTNativeTraceIsEnabled() && (count <= 8 || count % 128 == 0)) {
                FBTNativeTraceRecordBool((__bridge NSString *)captured->key, -1, mode);
            }
            return mode == 1;
        }
        BOOL original = captured->orig ? ((FBTBoolOrigImp)captured->orig)(receiver, captured->sel) : NO;
        __atomic_store_n(&captured->observedOriginal, original ? 1 : 0, __ATOMIC_RELAXED);
        __atomic_store_n(&captured->observedEffective, original ? 1 : 0, __ATOMIC_RELAXED);
        if (FBTNativeTraceIsEnabled() && (count <= 8 || count % 128 == 0)) {
            FBTNativeTraceRecordBool((__bridge NSString *)captured->key, original ? 1 : 0, original ? 1 : 0);
        }
        return original;
    });

    MSHookMessageEx(hookClass, sel, replacement, (IMP *)&desc->orig);

    pthread_mutex_lock(&sBoolLock);
    if (!sInstalled) sInstalled = [NSMutableDictionary dictionary];
    sInstalled[key] = [NSValue valueWithPointer:desc];
    [sInstallFailures removeObjectForKey:key];
    pthread_mutex_unlock(&sBoolLock);

    FBTLog(@"runtime bool hook instalado: %@", key);
    return YES;
}

void FBTRuntimeBoolMigrateLegacySymbolOverrides(void) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    static NSString *const marker = @"fbt_symbol_overrides_migrated_v1";
    if ([ud boolForKey:marker]) return;
    NSDictionary *legacy = [ud dictionaryForKey:@"fbt_symbol_overrides"];
    NSMutableDictionary *merged = [[FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    BOOL changed = NO;
    for (id key in legacy) {
        if (![key isKindOfClass:NSString.class]) continue;
        NSNumber *force = legacy[key];
        if (![force isKindOfClass:NSNumber.class] || merged[key]) continue;
        NSString *cls = nil, *selector = nil; BOOL meta = NO;
        if (!FBTBoolDecodeKey(key,&cls,&selector,&meta)) continue;
        merged[key] = @{@"class":cls,@"selector":selector,@"classMethod":@(meta),
                        @"force":@(force.boolValue),@"source":@"symbol-legacy"};
        changed = YES;
    }
    if (changed) [ud setObject:merged forKey:FBTKeyRuntimeBoolOverrides];
    [ud setBool:YES forKey:marker];
    if (changed) FBTRuntimeBoolReloadPrefs();
}
BOOL FBTRuntimeBoolInstallPersistedKey(NSString *key) {
    NSString *cls=nil,*selector=nil;BOOL meta=NO;
    if (!FBTBoolDecodeKey(key,&cls,&selector,&meta)) return NO;
    NSDictionary *entry=FBTRuntimeBoolOverridesSnapshot()[key];
    if (![entry[@"force"] respondsToSelector:@selector(boolValue)]) return NO;
    return FBTRuntimeBoolInstallOne(cls,selector,meta);
}
void FBTRuntimeBoolReinstallPersistedHooks(void) {
    FBTRuntimeBoolMigrateLegacySymbolOverrides();
    FBTRuntimeBoolReloadPrefs();
    if (!sBoolBrowserEnabled) return;
    NSDictionary *ovs = FBTRuntimeBoolOverridesSnapshot();
    for (NSString *key in ovs) {
        // Observation is session-scoped: preserve selection but do not
        // rearm a potentially unsafe hook automatically after a crash.
        NSDictionary *entry = [ovs[key] isKindOfClass:[NSDictionary class]] ? ovs[key] : nil;
        if ([entry[@"source"] isEqualToString:@"observe"]) continue;
        NSString *cls = nil;
        NSString *sel = nil;
        BOOL isClass = NO;
        if (!FBTBoolDecodeKey(key, &cls, &sel, &isClass)) continue;
        FBTRuntimeBoolInstallOne(cls, sel, isClass);
    }
}

// Called from an ordinary lifecycle callback, never from a dyld initializer.
// Only persisted targets are queried: no global Objective-C enumeration.
void FBTRuntimeBoolRetryPendingHooks(void) {
    static NSTimeInterval previous;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - previous < 10.0) return;
    previous = now;
    FBTRuntimeBoolReinstallPersistedHooks();
}

static BOOL FBTSelectorLooksUseful(NSString *sel) {
    NSString *s = sel.lowercaseString;
    // Avoid matching arbitrary names containing the 2-letter substring "is".
    NSArray *needles = @[@"enabled", @"enable", @"has", @"can", @"should", @"allow", @"supports", @"internal", @"employee", @"dogfood", @"dogfooding", @"dogfooder", @"debug", @"test", @"beta", @"force", @"gate", @"gating", @"eligible", @"isfbemployee", @"isinternal", @"isdebug", @"isdebugoptions", @"isdebugoverlay"];
    if ([s hasPrefix:@"is"] && s.length > 2) return YES;
    for (NSString *n in needles) if ([s containsString:n]) return YES;
    return NO;
}

static BOOL FBTClassLooksUseful(NSString *cls) {
    NSString *c = cls.lowercaseString;
    NSArray *needles = @[@"fb", @"meta", @"dogfood", @"dogfooding", @"mobileconfig", @"metaconfig", @"gating", @"gate", @"internal", @"internalsettings", @"employee", @"settings", @"tabbar", @"gemstone", @"dating", @"debug", @"debugoverlay", @"bugreport", @"userpreferences", @"react", @"rct", @"rn", @"bloks", @"xplat", @"mobileconfigfbt"];
    for (NSString *n in needles) if ([c containsString:n]) return YES;
    return NO;
}

static NSString *FBTBoolCategory(NSString *cls, NSString *sel) {
    NSString *hay = [[NSString stringWithFormat:@"%@ %@",cls ?: @"",sel ?: @""] lowercaseString];
    if ([hay containsString:@"employee"] || [hay containsString:@"fbuser"]) return @"Employee";
    if ([hay containsString:@"dogfood"] || [hay containsString:@"dogfooding"]) return @"Dogfood";
    if ([hay containsString:@"internal"] || [hay containsString:@"whitehat"]) return @"Internal";
    if ([hay containsString:@"mobileconfig"] || [hay containsString:@"metaconfig"]) return @"MobileConfig";
    if ([hay containsString:@"debug"] || [hay containsString:@"devmenu"]) return @"Debug";
    if ([hay containsString:@"gate"] || [hay containsString:@"eligible"]) return @"Gating";
    return @"Outro BOOL";
}
// Snapshot never enumerates the entire ObjC runtime: only selected or
// installed targets and explicit failed attempts. Read under a short lock;
// format the UI and compute counters after unlocking it.
NSArray<NSDictionary *> *FBTRuntimeBoolHookAuditSnapshot(void) {
    NSDictionary *preferences=nil, *issues=nil, *registered=nil;
    pthread_mutex_lock(&sBoolLock);
    preferences = [sOverrides copy] ?: @{};
    issues = [sInstallFailures copy] ?: @{};
    registered = [sInstalled copy] ?: @{};
    BOOL browserEnabled = sBoolBrowserEnabled;
    pthread_mutex_unlock(&sBoolLock);
    NSMutableSet<NSString *> *allKeys = [NSMutableSet setWithArray:preferences.allKeys];
    [allKeys addObjectsFromArray:issues.allKeys];
    [allKeys addObjectsFromArray:registered.allKeys];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSString *key in allKeys) {
        NSString *className=nil, *selector=nil; BOOL isClass=NO;
        if (!FBTBoolDecodeKey(key,&className,&selector,&isClass)) continue;
        NSDictionary *preference = [preferences[key] isKindOfClass:NSDictionary.class] ? preferences[key] : nil;
        NSDictionary *issue = [issues[key] isKindOfClass:NSDictionary.class] ? issues[key] : nil;
        FBTBoolHookDescriptor *desc = [registered[key] pointerValue];
        unsigned long long calls = desc ? __atomic_load_n(&desc->invocationCount,__ATOMIC_RELAXED) : 0;
        int original = desc ? __atomic_load_n(&desc->observedOriginal,__ATOMIC_ACQUIRE) : -1;
        int effective = desc ? __atomic_load_n(&desc->observedEffective,__ATOMIC_ACQUIRE) : -1;
        int mode = desc ? __atomic_load_n(&desc->forceMode,__ATOMIC_ACQUIRE) : -1;
        NSString *status = calls > 0 ? @"invoked" : desc ? @"registered" :
            issue[@"status"] ?: (preference ? @"pending" : @"not_requested");
        NSString *reason = issue[@"reason"];
        if (!reason.length && !desc) reason = @"Hook ainda não registrado";
        if (!reason.length && desc && calls == 0) reason = @"Trampoline registrado; aguardando primeira chamada";
        if (!reason.length && calls > 0) reason = @"Execução do wrapper observada";
        id force = preference[@"force"];
        [entries addObject:@{
            @"key": key, @"class": className ?: @"", @"selector": selector ?: @"",
            @"classMethod": @(isClass), @"category": FBTBoolCategory(className,selector),
            @"source": preference[@"source"] ?: @"runtime",
            @"status": status, @"reason": reason ?: @"",
            @"registered": @(desc != NULL), @"invoked": @(calls > 0),
            @"saved": @(preference != nil), @"masterEnabled": @(browserEnabled),
            @"forced": @([force respondsToSelector:@selector(boolValue)]),
            @"force": [force respondsToSelector:@selector(boolValue)] ? force : [NSNull null],
            @"activeForce": @(mode >= 0), @"invocationCount": @(calls),
            @"observedOriginal": original >= 0 ? @(original != 0) : [NSNull null],
            @"observedEffective": effective >= 0 ? @(effective != 0) : [NSNull null]
        }];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSArray *order = @[@"rejected",@"pending",@"registered",@"invoked",@"not_requested"];
        NSUInteger left = [order indexOfObject:a[@"status"]];
        NSUInteger right = [order indexOfObject:b[@"status"]];
        if (left != right) return left < right ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"key"] compare:b[@"key"] options:NSCaseInsensitiveSearch];
    }];
    return entries;
}

static NSInteger FBTBoolRelevance(NSDictionary *item) {
    NSString *c = item[@"category"];
    NSInteger score = [@[@"Employee",@"Internal",@"Dogfood",@"MobileConfig",@"Debug",@"Gating"] containsObject:c] ? 100 : 0;
    if ([item[@"hookInstalled"] boolValue]) score += 40;
    if ([item[@"forced"] boolValue]) score += 25;
    if ([item[@"invocationCount"] unsignedLongLongValue] > 0) score += 15;
    return score;
}
static void FBTAppendMethodsForClass(NSMutableArray *out, Class cls, BOOL classMethods, NSString *query, NSUInteger limit) {
    Class methodClass = classMethods ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(methodClass, &count);
    NSString *className = NSStringFromClass(cls);
    NSString *q = query.lowercaseString;
    for (unsigned int i = 0; i < count && out.count < limit; i++) {
        Method m = methods[i];
        if (method_getNumberOfArguments(m) != 2) continue;
        char ret[16] = {0};
        method_getReturnType(m, ret, sizeof(ret));
        if (!(ret[0] == 'B' || ret[0] == 'c')) continue;
        NSString *sel = NSStringFromSelector(method_getName(m));
        NSString *imagePath = FBTImagePathForMethod(m);
        NSString *imageKind = FBTImageKindForPath(imagePath);
        NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@ %@", className, sel, imageKind ?: @"", imagePath ?: @""] lowercaseString];
        if (q.length) {
            if (!FBTQueryMatchesHaystack(q, hay)) continue;
        } else {
            if (!FBTSelectorLooksUseful(sel) && !FBTClassLooksUseful(className)) continue;
        }
        NSString *key = FBTBoolKey(className, sel, classMethods);
        NSDictionary *ov = FBTBoolOverrideForKey(key);
        BOOL hasForce = [ov[@"force"] respondsToSelector:@selector(boolValue)];
        pthread_mutex_lock(&sBoolLock);
        FBTBoolHookDescriptor *desc = [sInstalled[key] pointerValue];
        pthread_mutex_unlock(&sBoolLock);
        int original = desc ? __atomic_load_n(&desc->observedOriginal, __ATOMIC_RELAXED) : -1;
        int effective = desc ? __atomic_load_n(&desc->observedEffective, __ATOMIC_RELAXED) : -1;
        unsigned long long count = desc ? __atomic_load_n(&desc->invocationCount, __ATOMIC_RELAXED) : 0;
        [out addObject:@{
            @"hookInstalled": @(desc != NULL),
            @"installState": desc ? @"installed" : (ov ? @"pending" : @"not_requested"),
            @"observedOriginal": original < 0 ? [NSNull null] : @(original != 0),
            @"observedEffective": effective < 0 ? [NSNull null] : @(effective != 0),
            @"invocationCount": @(count),
            @"class": className ?: @"",
            @"selector": sel ?: @"",
            @"category": FBTBoolCategory(className, sel),
            @"signature": [NSString stringWithFormat:@"%@ (%@)", ret[0] == 'B' ? @"BOOL" : @"char/BOOL", method_getTypeEncoding(m) ? [NSString stringWithUTF8String:method_getTypeEncoding(m)] : @"unknown"],
            @"classMethod": @(classMethods),
            @"key": key ?: @"",
            @"image": imagePath ?: @"",
            @"imageKind": imageKind ?: @"unknown",
            @"forced": @(hasForce),
            @"observing": @(ov != nil && !hasForce),
            @"force": ov[@"force"] ?: [NSNull null],
        }];
    }
    if (methods) free(methods);
}

NSArray<NSDictionary *> *FBTRuntimeBoolSearch(NSString *query, NSUInteger limit) {
    if (limit == 0) limit = 300;
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return @[];
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) return @[];
    classCount = objc_getClassList(classes, classCount);
    NSMutableArray *out = [NSMutableArray array];
    // Scan a larger bounded pool before ranking; stopping at the first few
    // classes previously hid the selectors the user was actually looking for.
    NSUInteger scanLimit = query.length ? MAX(limit, 2400) : MAX(limit, 1600);
    for (int i = 0; i < classCount && out.count < scanLimit; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        NSString *className = NSStringFromClass(cls);
        // Não pré-filtra por nome de classe quando a query está vazia.
        // O bug real do browser era este: classes com selector útil (-isEmployee,
        // -isDebugOptionsEnabled etc.) sumiam se o nome da classe não continha
        // FB/Dogfood/MobileConfig. A filtragem correta acontece por método.
        (void)className;
        @autoreleasepool {
            FBTAppendMethodsForClass(out, cls, NO, query ?: @"", scanLimit);
            FBTAppendMethodsForClass(out, cls, YES, query ?: @"", scanLimit);
        }
    }
    free(classes);
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger sa=FBTBoolRelevance(a), sb=FBTBoolRelevance(b);
        if (sa!=sb) return sa>sb ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"key"] compare:b[@"key"] options:NSCaseInsensitiveSearch];
    }];
    if (out.count > limit) return [out subarrayWithRange:NSMakeRange(0, limit)];
    return out;
}

static NSMutableDictionary *sSweepStats;

static BOOL FBTSweepCandidateMatches(NSDictionary *hit, NSString *mode) {
    NSString *selector = hit[@"selector"] ?: @"";
    NSString *m = mode.lowercaseString ?: @"";

    NSDictionary<NSString *, NSSet<NSString *> *> *allowlists = @{
        @"dogfood": [NSSet setWithArray:@[
            @"enableDogfoodingView", @"triageToDogfoodingAssistantSession",
            @"isDogfooder", @"isDogfooding", @"dogfoodingEnabled", @"isDogfoodEnabled"
        ]],
        @"internaldebug": [NSSet setWithArray:@[
            @"devMenuEnabled", @"isDeviceDebuggingAvailable",
            @"isShakeToShowDevMenuEnabled", @"isShakeGestureEnabled",
            @"isDebugOptionsEnabled", @"isDebugOverlayEnabled",
            @"isInternalSettingsEnabled", @"isInternalBuild"
        ]],
    };
    NSSet<NSString *> *allowed = allowlists[m];
    return allowed && [allowed containsObject:selector];
}

static void FBTRuntimeBoolSetOverrideWithSource(NSDictionary *candidate,
                                                BOOL forcedValue,
                                                NSString *source) {
    NSString *className = candidate[@"class"];
    NSString *selectorName = candidate[@"selector"];
    BOOL isClass = [candidate[@"classMethod"] boolValue];
    NSString *key = FBTBoolKey(className, selectorName, isClass);
    // Persist first; a class absent during startup remains pending.
    NSMutableDictionary *all = [[FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [@{
        @"class": className ?: @"",
        @"selector": selectorName ?: @"",
        @"classMethod": @(isClass),
        @"force": @(forcedValue),
    } mutableCopy];
    if (source.length) entry[@"source"] = source;
    all[key] = entry;
    [FBTDefaults setDict:all forKey:FBTKeyRuntimeBoolOverrides];
    FBTRuntimeBoolReloadPrefs();
    if (!FBTRuntimeBoolInstallOne(className, selectorName, isClass)) {
        FBTLog(@"runtime bool pendente (classe ausente): %@", key);
    }
}

NSUInteger FBTRuntimeBoolInstallSweep(NSString *mode, BOOL forcedValue, NSUInteger limit) {
    if (limit == 0) limit = 120;
    FBTRuntimeBoolReloadPrefs();
    if (![FBTDefaults boolForKey:FBTKeyRuntimeBoolBrowserEnabled]) {
        FBTLog(@"runtime BOOL sweep denied: browser master toggle disabled");
        return 0;
    }

    NSDictionary<NSString *, NSArray<NSString *> *> *queriesByMode = @{
        @"dogfood": @[@"enableDogfoodingView", @"triageToDogfoodingAssistantSession", @"isDogfooder", @"isDogfooding", @"dogfoodingEnabled", @"isDogfoodEnabled"],
        @"internaldebug": @[@"devMenuEnabled", @"isDeviceDebuggingAvailable", @"isShakeToShowDevMenuEnabled", @"isShakeGestureEnabled", @"isDebugOptionsEnabled", @"isDebugOverlayEnabled", @"isInternalSettingsEnabled", @"isInternalBuild"],
    };

    NSString *normalizedMode = mode.lowercaseString ?: @"";
    NSArray<NSString *> *queries = queriesByMode[normalizedMode] ?: @[];
    NSString *source = [@"sweep:" stringByAppendingString:normalizedMode];
    NSMutableDictionary *seen = [NSMutableDictionary dictionary];
    NSUInteger installed = 0, rejected = 0, alreadyOwned = 0;
    NSDictionary *existing = FBTRuntimeBoolOverridesSnapshot();

    for (NSString *q in queries) {
        NSArray<NSDictionary *> *hits = FBTRuntimeBoolSearch(q, 600);
        for (NSDictionary *hit in hits) {
            NSString *key = hit[@"key"] ?: @"";
            if (!key.length || seen[key]) continue;
            seen[key] = @YES;
            if (!FBTSweepCandidateMatches(hit, normalizedMode)) continue;
            NSDictionary *existingEntry = [existing[key] isKindOfClass:NSDictionary.class] ? existing[key] : nil;
            NSString *currentSource = existingEntry[@"source"];
            if (existingEntry && ![currentSource isEqualToString:source]) {
                ++alreadyOwned; // Never overwrite a manual/other family override.
                continue;
            }
            if (!FBTRuntimeBoolInstallOne(hit[@"class"],hit[@"selector"],[hit[@"classMethod"] boolValue])) {
                ++rejected; // Does not count as installed or persist unhookable rows.
                continue;
            }
            FBTRuntimeBoolSetOverrideWithSource(hit, forcedValue, source);
            if (FBTRuntimeBoolHookInstalledForKey(key)) ++installed;
            if (installed >= limit) break;
        }
        if (installed >= limit) break;
    }

    if (!sSweepStats) sSweepStats = [NSMutableDictionary dictionary];
    sSweepStats[mode ?: @"unknown"] = @{
        @"installed": @(installed),
        @"rejected": @(rejected),
        @"skipped_other_owner": @(alreadyOwned),
        @"force": @(forcedValue),
        @"limit": @(limit),
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };
    FBTLog(@"runtime bool sweep %@ installed=%lu", mode, (unsigned long)installed);
    return installed;
}

NSDictionary *FBTRuntimeBoolSweepStats(void) {
    return [sSweepStats copy] ?: @{};
}

void FBTRuntimeBoolSetOverride(NSDictionary *candidate, BOOL forcedValue) {
    FBTRuntimeBoolSetOverrideWithSource(candidate, forcedValue, @"manual");
}

// Installs a passive observer without changing return values; persists exact target.
void FBTRuntimeBoolObserve(NSDictionary *candidate) {
    NSString *className = candidate[@"class"];
    NSString *selectorName = candidate[@"selector"];
    if (!className.length || !selectorName.length) return;
    BOOL isClassMethod = [candidate[@"classMethod"] boolValue];
    NSString *key = FBTBoolKey(className, selectorName, isClassMethod);
    NSMutableDictionary *all = [[FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[key] = @{ @"class": className, @"selector": selectorName,
                  @"classMethod": @(isClassMethod), @"source": @"observe" };
    [FBTDefaults setDict:all forKey:FBTKeyRuntimeBoolOverrides];
    FBTRuntimeBoolReloadPrefs();
    FBTRuntimeBoolInstallOne(className, selectorName, isClassMethod);
}

void FBTRuntimeBoolClearOverride(NSDictionary *candidate) {
    NSString *key = candidate[@"key"];
    if (!key.length) key = FBTBoolKey(candidate[@"class"], candidate[@"selector"], [candidate[@"classMethod"] boolValue]);
    NSMutableDictionary *all = [[FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    [all removeObjectForKey:key];
    [FBTDefaults setDict:all forKey:FBTKeyRuntimeBoolOverrides];
    FBTRuntimeBoolReloadPrefs();
}

void FBTRuntimeBoolClearSweep(NSString *mode) {
    NSString *source = [@"sweep:" stringByAppendingString:(mode.lowercaseString ?: @"")];
    NSMutableDictionary *all = [[FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSArray *keys = [all allKeys];
    BOOL changed = NO;
    for (NSString *key in keys) {
        NSDictionary *entry = [all[key] isKindOfClass:[NSDictionary class]] ? all[key] : nil;
        if ([entry[@"source"] isEqualToString:source]) {
            [all removeObjectForKey:key];
            changed = YES;
        }
    }
    if (!changed) return;
    [FBTDefaults setDict:all forKey:FBTKeyRuntimeBoolOverrides];
    FBTRuntimeBoolReloadPrefs();
}

void FBTRuntimeBoolClearAllOverrides(void) {
    [FBTDefaults setDict:@{} forKey:FBTKeyRuntimeBoolOverrides];
    FBTRuntimeBoolReloadPrefs();
}
