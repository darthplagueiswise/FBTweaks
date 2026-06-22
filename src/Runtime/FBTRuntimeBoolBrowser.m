#import "FBTRuntimeBoolBrowser.h"
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
} FBTBoolHookDescriptor;

static NSMutableDictionary<NSString *, NSValue *> *sInstalled; // key -> descriptor ptr
static NSDictionary *sOverrides;                                // key -> {force,class,selector,classMethod}
static BOOL sBoolBrowserEnabled = NO;
static pthread_mutex_t sBoolLock = PTHREAD_MUTEX_INITIALIZER;


static NSString *FBTImageKindForPath(NSString *path) {
    NSString *p = path ?: @"";
    NSString *last = p.lastPathComponent ?: @"";
    if ([last isEqualToString:@"Facebook"] || [last isEqualToString:@"Instagram"]) return @"main-exec";
    if ([last containsString:@"FBSharedFramework"]) return @"FBSharedFramework";
    if ([p containsString:@"/Frameworks/"]) return @"framework";
    if ([p containsString:@"/System/Library/"]) return @"system";
    return last.length ? last : @"unknown";
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
    NSDictionary *ov = sOverrides[key];
    return [ov isKindOfClass:[NSDictionary class]] ? ov : nil;
}

static void FBTBoolRememberObserved(NSString *key, BOOL value) {
    // Mantém a observação fora do defaults para não gravar em hot path.
    // Reservado para UI futura; hoje o importante é não ler defaults aqui.
    (void)key; (void)value;
}

void FBTRuntimeBoolReloadPrefs(void) {
    sBoolBrowserEnabled = [FBTDefaults boolForKey:FBTKeyRuntimeBoolBrowserEnabled];
    NSDictionary *raw = [FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides];
    sOverrides = [raw copy] ?: @{};
}

NSDictionary *FBTRuntimeBoolOverridesSnapshot(void) {
    return sOverrides ?: @{};
}

static BOOL FBTRuntimeBoolInstallOne(NSString *className, NSString *selectorName, BOOL isClassMethod) {
    if (!className.length || !selectorName.length) return NO;
    NSString *key = FBTBoolKey(className, selectorName, isClassMethod);

    pthread_mutex_lock(&sBoolLock);
    if (sInstalled[key]) { pthread_mutex_unlock(&sBoolLock); return YES; }
    pthread_mutex_unlock(&sBoolLock);

    Class cls = objc_getClass(className.UTF8String);
    if (!cls) return NO;
    Class hookClass = isClassMethod ? object_getClass(cls) : cls;
    SEL sel = NSSelectorFromString(selectorName);
    Method m = class_getInstanceMethod(hookClass, sel);
    if (!m) return NO;
    if (method_getNumberOfArguments(m) != 2) return NO;
    char ret[16] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (!(ret[0] == 'B' || ret[0] == 'c')) return NO;

    FBTBoolHookDescriptor *desc = calloc(1, sizeof(FBTBoolHookDescriptor));
    if (!desc) return NO;
    desc->sel = sel;
    desc->key = (CFStringRef)CFBridgingRetain(key);

    __block FBTBoolHookDescriptor *captured = desc;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver) {
        BOOL original = NO;
        if (captured->orig) {
            original = ((FBTBoolOrigImp)captured->orig)(receiver, captured->sel);
        }
        NSString *capturedKey = (__bridge NSString *)captured->key;
        FBTBoolRememberObserved(capturedKey, original);
        NSDictionary *ov = FBTBoolOverrideForKey(capturedKey);
        if (ov && sBoolBrowserEnabled) {
            id v = ov[@"force"];
            if ([v respondsToSelector:@selector(boolValue)]) return [v boolValue];
        }
        return original;
    });

    MSHookMessageEx(hookClass, sel, replacement, (IMP *)&desc->orig);

    pthread_mutex_lock(&sBoolLock);
    if (!sInstalled) sInstalled = [NSMutableDictionary dictionary];
    sInstalled[key] = [NSValue valueWithPointer:desc];
    pthread_mutex_unlock(&sBoolLock);

    FBTLog(@"runtime bool hook instalado: %@", key);
    return YES;
}

void FBTRuntimeBoolReinstallPersistedHooks(void) {
    FBTRuntimeBoolReloadPrefs();
    if (!sBoolBrowserEnabled) return;
    NSDictionary *ovs = sOverrides ?: @{};
    for (NSString *key in ovs) {
        NSString *cls = nil;
        NSString *sel = nil;
        BOOL isClass = NO;
        if (!FBTBoolDecodeKey(key, &cls, &sel, &isClass)) continue;
        FBTRuntimeBoolInstallOne(cls, sel, isClass);
    }
}

static BOOL FBTSelectorLooksUseful(NSString *sel) {
    NSString *s = sel.lowercaseString;
    NSArray *needles = @[@"enabled", @"enable", @"is", @"has", @"can", @"should", @"allow", @"supports", @"internal", @"employee", @"dogfood", @"debug", @"test", @"beta", @"force", @"gate", @"eligible"];
    for (NSString *n in needles) if ([s containsString:n]) return YES;
    return NO;
}

static BOOL FBTClassLooksUseful(NSString *cls) {
    NSString *c = cls.lowercaseString;
    NSArray *needles = @[@"fb", @"meta", @"dogfood", @"mobileconfig", @"gating", @"gate", @"internal", @"employee", @"settings", @"tabbar", @"gemstone", @"dating", @"debug"];
    for (NSString *n in needles) if ([c containsString:n]) return YES;
    return NO;
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
            if ([hay rangeOfString:q].location == NSNotFound) continue;
        } else {
            if (!FBTSelectorLooksUseful(sel) && !FBTClassLooksUseful(className)) continue;
        }
        NSString *key = FBTBoolKey(className, sel, classMethods);
        NSDictionary *ov = FBTBoolOverrideForKey(key);
        [out addObject:@{
            @"class": className ?: @"",
            @"selector": sel ?: @"",
            @"classMethod": @(classMethods),
            @"key": key ?: @"",
            @"image": imagePath ?: @"",
            @"imageKind": imageKind ?: @"unknown",
            @"forced": ov ? @YES : @NO,
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
    for (int i = 0; i < classCount && out.count < limit; i++) {
        Class cls = classes[i];
        if (!cls) continue;
        NSString *className = NSStringFromClass(cls);
        if (query.length == 0 && !FBTClassLooksUseful(className)) continue;
        FBTAppendMethodsForClass(out, cls, NO, query ?: @"", limit);
        FBTAppendMethodsForClass(out, cls, YES, query ?: @"", limit);
    }
    free(classes);
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"key"] compare:b[@"key"] options:NSCaseInsensitiveSearch];
    }];
    return out;
}


static NSMutableDictionary *sSweepStats;

static BOOL FBTStringContainsAny(NSString *hay, NSArray<NSString *> *needles) {
    NSString *h = hay.lowercaseString ?: @"";
    for (NSString *n in needles) {
        if ([h rangeOfString:n.lowercaseString].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL FBTSweepCandidateMatches(NSDictionary *hit, NSString *mode) {
    NSString *cls = hit[@"class"] ?: @"";
    NSString *sel = hit[@"selector"] ?: @"";
    NSString *imageKind = hit[@"imageKind"] ?: @"";
    NSString *image = hit[@"image"] ?: @"";
    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@", cls, sel, imageKind, image];
    NSString *m = mode.lowercaseString ?: @"";

    if ([m isEqualToString:@"employee"]) {
        return FBTStringContainsAny(hay, @[
            @"employee", @"vieweremployee", @"testuser", @"internaltestuser", @"is_employee", @"employeeortest"
        ]);
    }
    if ([m isEqualToString:@"dogfood"]) {
        return FBTStringContainsAny(hay, @[
            @"dogfood", @"dogfooding", @"dogfooder", @"fbt", @"metaconfig"
        ]);
    }
    if ([m isEqualToString:@"internaldebug"]) {
        return FBTStringContainsAny(hay, @[
            @"internalsettings", @"internaltool", @"debugmenu", @"debug menu", @"debugcontroller", @"debugview", @"developer", @"devmenu"
        ]);
    }
    return NO;
}

NSUInteger FBTRuntimeBoolInstallSweep(NSString *mode, BOOL forcedValue, NSUInteger limit) {
    if (limit == 0) limit = 120;
    FBTRuntimeBoolReloadPrefs();
    sBoolBrowserEnabled = YES;

    NSDictionary<NSString *, NSArray<NSString *> *> *queriesByMode = @{
        @"employee": @[@"employee", @"viewerEmployee", @"internalTestUser", @"testUser", @"is_employee"],
        @"dogfood": @[@"dogfood", @"dogfooding", @"dogfooder", @"FBDogFood", @"DogFood"],
        @"internaldebug": @[@"internalSettings", @"internalTools", @"debugMenu", @"DebugMenu", @"developer"]
    };
    NSArray<NSString *> *queries = queriesByMode[mode.lowercaseString ?: @""] ?: @[];
    NSMutableDictionary *seen = [NSMutableDictionary dictionary];
    NSUInteger installed = 0;
    for (NSString *q in queries) {
        NSArray<NSDictionary *> *hits = FBTRuntimeBoolSearch(q, 600);
        for (NSDictionary *hit in hits) {
            NSString *key = hit[@"key"] ?: @"";
            if (!key.length || seen[key]) continue;
            seen[key] = @YES;
            if (!FBTSweepCandidateMatches(hit, mode)) continue;
            FBTRuntimeBoolSetOverride(hit, forcedValue);
            installed++;
            if (installed >= limit) break;
        }
        if (installed >= limit) break;
    }
    if (!sSweepStats) sSweepStats = [NSMutableDictionary dictionary];
    sSweepStats[mode ?: @"unknown"] = @{
        @"installed": @(installed),
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
    NSString *className = candidate[@"class"];
    NSString *selectorName = candidate[@"selector"];
    BOOL isClass = [candidate[@"classMethod"] boolValue];
    NSString *key = FBTBoolKey(className, selectorName, isClass);
    if (!FBTRuntimeBoolInstallOne(className, selectorName, isClass)) return;
    NSMutableDictionary *all = [[FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[key] = @{ @"class": className ?: @"", @"selector": selectorName ?: @"", @"classMethod": @(isClass), @"force": @(forcedValue) };
    [FBTDefaults setDict:all forKey:FBTKeyRuntimeBoolOverrides];
    FBTRuntimeBoolReloadPrefs();
}

void FBTRuntimeBoolClearOverride(NSDictionary *candidate) {
    NSString *key = candidate[@"key"];
    if (!key.length) key = FBTBoolKey(candidate[@"class"], candidate[@"selector"], [candidate[@"classMethod"] boolValue]);
    NSMutableDictionary *all = [[FBTDefaults dictForKey:FBTKeyRuntimeBoolOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    [all removeObjectForKey:key];
    [FBTDefaults setDict:all forKey:FBTKeyRuntimeBoolOverrides];
    FBTRuntimeBoolReloadPrefs();
}

void FBTRuntimeBoolClearAllOverrides(void) {
    [FBTDefaults setDict:@{} forKey:FBTKeyRuntimeBoolOverrides];
    FBTRuntimeBoolReloadPrefs();
}
