#import "FBGRBoolRuntimeInventory.h"
#import "FBGRLog.h"
#import "../FBGramPrefix.h"
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation FBGRBoolRuntimeCandidate
- (NSString *)stableKey {
    return [NSString stringWithFormat:@"%@|%@|%@|%@",
        self.imageKindName ?: @"?",
        self.className ?: @"?",
        self.classMethod ? @"+" : @"-",
        self.selectorName ?: @"?"];
}
- (NSString *)displayTitle {
    return [NSString stringWithFormat:@"%@[%@ %@]",
        self.classMethod ? @"+ " : @"- ", self.className ?: @"?", self.selectorName ?: @"?"];
}
- (NSString *)displaySubtitle {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:self.typeEncoding ?: @"B@:"];
    [parts addObject:self.hooked ? @"hook instalado" : @"hook sob demanda"];
    if (self.overrideSet) [parts addObject:[NSString stringWithFormat:@"FORÇADO=%@", self.overrideValue ? @"YES" : @"NO"]];
    return [parts componentsJoinedByString:@" · "];
}
@end

#define FBGR_BOOL_MAX_HOOKS 4096

typedef BOOL (*FBGRBoolOrigIMP)(id, SEL);
typedef struct { Class hookClass; SEL sel; BOOL isClassMethod; IMP original; } FBGRBoolHookEntry;
static FBGRBoolHookEntry gBoolHooks[FBGR_BOOL_MAX_HOOKS];
static NSUInteger gBoolHookCount = 0;
static NSMutableDictionary<NSString *, NSNumber *> *gBoolOverrides;
static NSMutableDictionary<NSString *, FBGRBoolRuntimeCandidate *> *gCandidateByKey;
static NSArray<FBGRBoolRuntimeCandidate *> *gExecutableCandidates;
static NSArray<FBGRBoolRuntimeCandidate *> *gFBSharedCandidates;
static BOOL gWarmOverrides = NO;

static NSString *FBGRBoolOverridePrefix(void) { return @"fbgr.bool."; }
static NSString *FBGRBoolPrefKey(NSString *stableKey) { return [FBGRBoolOverridePrefix() stringByAppendingString:stableKey ?: @"?"]; }

NSString *FBGRBoolRuntimeImageTitle(FBGRBoolRuntimeImageKind kind) {
    return kind == FBGRBoolRuntimeImageKindExecutable ? @"Executable Bool Runtime" : @"FBSharedFramework Bool Runtime";
}

static NSString *FBGRBoolImageKindName(FBGRBoolRuntimeImageKind kind) {
    return kind == FBGRBoolRuntimeImageKindExecutable ? @"Facebook" : @"FBSharedFramework";
}

static BOOL FBGRBoolImageMatches(const char *imageName, FBGRBoolRuntimeImageKind kind) {
    if (!imageName) return NO;
    NSString *img = [NSString stringWithUTF8String:imageName] ?: @"";
    if (kind == FBGRBoolRuntimeImageKindExecutable) {
        NSString *exec = NSBundle.mainBundle.executablePath ?: @"";
        return [img isEqualToString:exec] || [img hasSuffix:@"/Facebook.app/Facebook"];
    }
    return [img containsString:@"/FBSharedFramework.framework/FBSharedFramework"];
}

static BOOL FBGRBoolReturnTypeIsBool(Method m) {
    char *ret = method_copyReturnType(m);
    if (!ret) return NO;
    BOOL ok = (ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C');
    free(ret);
    return ok;
}

static BOOL FBGRBoolSelectorLooksPatchable(SEL sel) {
    if (!sel) return NO;
    const char *name = sel_getName(sel);
    if (!name || !name[0]) return NO;
    NSString *s = [NSString stringWithUTF8String:name] ?: @"";
    if ([s hasPrefix:@"set"] || [s containsString:@":"]) return NO;
    if ([s isEqualToString:@"class"] || [s isEqualToString:@"superclass"] || [s isEqualToString:@"isProxy"] || [s isEqualToString:@"respondsToSelector"]) return NO;
    return YES;
}

static void FBGRBoolWarmOverrides(void) {
    if (gWarmOverrides) return;
    gBoolOverrides = [NSMutableDictionary dictionary];
    NSDictionary *all = [FBGRPrefs() dictionaryRepresentation];
    NSString *prefix = FBGRBoolOverridePrefix();
    for (NSString *key in all.allKeys) {
        if (![key hasPrefix:prefix]) continue;
        NSString *stable = [key substringFromIndex:prefix.length];
        gBoolOverrides[stable] = @([FBGRPrefs() boolForKey:key]);
    }
    gWarmOverrides = YES;
}

static BOOL FBGRBoolOverrideForStableKey(NSString *key, BOOL *outValue) {
    FBGRBoolWarmOverrides();
    NSNumber *n = key ? gBoolOverrides[key] : nil;
    if (!n) return NO;
    if (outValue) *outValue = n.boolValue;
    return YES;
}

static NSString *FBGRBoolStableKeyForCall(id self, SEL _cmd, BOOL *isClassMethodOut) {
    BOOL isClassMethod = object_isClass(self);
    if (isClassMethodOut) *isClassMethodOut = isClassMethod;
    Class namedClass = isClassMethod ? (Class)self : object_getClass(self);
    const char *cn = namedClass ? class_getName(namedClass) : "?";
    NSString *className = cn ? [NSString stringWithUTF8String:cn] : @"?";
    NSString *selectorName = NSStringFromSelector(_cmd) ?: @"?";
    const char *img = namedClass ? class_getImageName(namedClass) : NULL;
    NSString *imageKind = FBGRBoolImageMatches(img, FBGRBoolRuntimeImageKindFBSharedFramework)
        ? @"FBSharedFramework"
        : @"Facebook";
    return [NSString stringWithFormat:@"%@|%@|%@|%@", imageKind, className, isClassMethod ? @"+" : @"-", selectorName];
}

static IMP FBGRBoolOriginalForCall(id self, SEL _cmd) {
    Class hookClass = object_getClass(self);
    for (NSUInteger i = 0; i < gBoolHookCount; i++) {
        if (gBoolHooks[i].hookClass == hookClass && gBoolHooks[i].sel == _cmd) return gBoolHooks[i].original;
    }
    return NULL;
}

static BOOL h_boolRuntimeGetter(id self, SEL _cmd) {
    BOOL value = NO;
    NSString *key = FBGRBoolStableKeyForCall(self, _cmd, NULL);
    if (FBGRBoolOverrideForStableKey(key, &value)) return value;
    IMP orig = FBGRBoolOriginalForCall(self, _cmd);
    return orig ? ((FBGRBoolOrigIMP)orig)(self, _cmd) : NO;
}

static FBGRBoolRuntimeCandidate *FBGRBoolCandidateFromMethod(Class cls, Method m, BOOL classMethod, FBGRBoolRuntimeImageKind kind, const char *imageName) {
    if (!cls || !m) return nil;
    if (method_getNumberOfArguments(m) != 2) return nil;
    if (!FBGRBoolReturnTypeIsBool(m)) return nil;
    SEL sel = method_getName(m);
    if (!FBGRBoolSelectorLooksPatchable(sel)) return nil;

    char *types = method_copyReturnType(m);
    FBGRBoolRuntimeCandidate *c = [FBGRBoolRuntimeCandidate new];
    c.imageKindName = FBGRBoolImageKindName(kind);
    c.imagePath = imageName ? [NSString stringWithUTF8String:imageName] : @"";
    c.className = [NSString stringWithUTF8String:class_getName(cls)] ?: @"?";
    c.selectorName = NSStringFromSelector(sel) ?: @"?";
    c.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"B";
    c.classMethod = classMethod;
    if (types) free(types);
    BOOL val = NO;
    c.overrideSet = FBGRBoolOverrideForStableKey(c.stableKey, &val);
    c.overrideValue = val;
    c.hooked = NO;
    return c;
}

static NSArray<FBGRBoolRuntimeCandidate *> *FBGRBoolBuildCandidates(FBGRBoolRuntimeImageKind kind) {
    FBGRBoolWarmOverrides();
    NSMutableArray<FBGRBoolRuntimeCandidate *> *out = [NSMutableArray array];
    if (!gCandidateByKey) gCandidateByKey = [NSMutableDictionary dictionary];

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        const char *imageName = class_getImageName(cls);
        if (!FBGRBoolImageMatches(imageName, kind)) continue;

        unsigned int n = 0;
        Method *methods = class_copyMethodList(cls, &n);
        for (unsigned int j = 0; j < n; j++) {
            FBGRBoolRuntimeCandidate *c = FBGRBoolCandidateFromMethod(cls, methods[j], NO, kind, imageName);
            if (c) { [out addObject:c]; gCandidateByKey[c.stableKey] = c; }
        }
        if (methods) free(methods);

        Class meta = object_getClass(cls);
        n = 0;
        methods = class_copyMethodList(meta, &n);
        for (unsigned int j = 0; j < n; j++) {
            FBGRBoolRuntimeCandidate *c = FBGRBoolCandidateFromMethod(cls, methods[j], YES, kind, imageName);
            if (c) { [out addObject:c]; gCandidateByKey[c.stableKey] = c; }
        }
        if (methods) free(methods);
    }
    if (classes) free(classes);

    [out sortUsingComparator:^NSComparisonResult(FBGRBoolRuntimeCandidate *a, FBGRBoolRuntimeCandidate *b) {
        NSComparisonResult r = [a.className compare:b.className options:NSCaseInsensitiveSearch];
        if (r != NSOrderedSame) return r;
        return [a.selectorName compare:b.selectorName options:NSCaseInsensitiveSearch];
    }];
    FBGRLogHook("BoolRuntime", "%@ candidates=%lu", FBGRBoolImageKindName(kind), (unsigned long)out.count);
    return out;
}

NSArray<FBGRBoolRuntimeCandidate *> *FBGRBoolRuntimeCandidates(FBGRBoolRuntimeImageKind kind, BOOL forceRefresh) {
    if (kind == FBGRBoolRuntimeImageKindExecutable) {
        if (!gExecutableCandidates || forceRefresh) gExecutableCandidates = FBGRBoolBuildCandidates(kind);
        return gExecutableCandidates ?: @[];
    }
    if (!gFBSharedCandidates || forceRefresh) gFBSharedCandidates = FBGRBoolBuildCandidates(kind);
    return gFBSharedCandidates ?: @[];
}

FBGRBoolRuntimeCandidate *FBGRBoolRuntimeCandidateForKey(NSString *key) {
    if (!key.length) return nil;
    if (!gCandidateByKey) gCandidateByKey = [NSMutableDictionary dictionary];
    return gCandidateByKey[key];
}

BOOL FBGRBoolRuntimeInstallHook(FBGRBoolRuntimeCandidate *candidate, NSError **error) {
    if (!candidate.className.length || !candidate.selectorName.length) return NO;
    Class cls = NSClassFromString(candidate.className);
    if (!cls) {
        if (error) *error = [NSError errorWithDomain:@"FBGRBoolRuntime" code:1 userInfo:@{NSLocalizedDescriptionKey:@"classe ausente"}];
        return NO;
    }
    SEL sel = NSSelectorFromString(candidate.selectorName);
    Method m = candidate.classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m || method_getNumberOfArguments(m) != 2 || !FBGRBoolReturnTypeIsBool(m)) {
        if (error) *error = [NSError errorWithDomain:@"FBGRBoolRuntime" code:2 userInfo:@{NSLocalizedDescriptionKey:@"método não é BOOL getter simples"}];
        return NO;
    }
    Class hookClass = candidate.classMethod ? object_getClass(cls) : cls;
    for (NSUInteger i = 0; i < gBoolHookCount; i++) {
        if (gBoolHooks[i].hookClass == hookClass && gBoolHooks[i].sel == sel) { candidate.hooked = YES; return YES; }
    }
    if (gBoolHookCount >= FBGR_BOOL_MAX_HOOKS) return NO;
    IMP orig = NULL;
    MSHookMessageEx(hookClass, sel, (IMP)h_boolRuntimeGetter, &orig);
    if (!orig) return NO;
    gBoolHooks[gBoolHookCount++] = (FBGRBoolHookEntry){ hookClass, sel, candidate.classMethod, orig };
    candidate.hooked = YES;
    FBGRLogHook("BoolRuntime", "hooked %@", candidate.stableKey);
    return YES;
}

void FBGRBoolRuntimeSetOverride(FBGRBoolRuntimeCandidate *candidate, BOOL value) {
    if (!candidate.stableKey.length) return;
    FBGRBoolWarmOverrides();
    gBoolOverrides[candidate.stableKey] = @(value);
    [FBGRPrefs() setBool:value forKey:FBGRBoolPrefKey(candidate.stableKey)];
    [FBGRPrefs() synchronize];
    candidate.overrideSet = YES;
    candidate.overrideValue = value;
    NSError *err = nil;
    FBGRBoolRuntimeInstallHook(candidate, &err);
}

void FBGRBoolRuntimeClearOverride(FBGRBoolRuntimeCandidate *candidate) {
    if (!candidate.stableKey.length) return;
    FBGRBoolWarmOverrides();
    [gBoolOverrides removeObjectForKey:candidate.stableKey];
    [FBGRPrefs() removeObjectForKey:FBGRBoolPrefKey(candidate.stableKey)];
    [FBGRPrefs() synchronize];
    candidate.overrideSet = NO;
}

void FBGRBoolRuntimeClearAllForImageKind(FBGRBoolRuntimeImageKind kind) {
    FBGRBoolWarmOverrides();
    NSString *prefix = [FBGRBoolImageKindName(kind) stringByAppendingString:@"|"];
    for (NSString *stable in gBoolOverrides.allKeys.copy) {
        if (![stable hasPrefix:prefix]) continue;
        [gBoolOverrides removeObjectForKey:stable];
        [FBGRPrefs() removeObjectForKey:FBGRBoolPrefKey(stable)];
    }
    [FBGRPrefs() synchronize];
}

NSUInteger FBGRBoolRuntimeOverrideCountForImageKind(FBGRBoolRuntimeImageKind kind) {
    FBGRBoolWarmOverrides();
    NSString *prefix = [FBGRBoolImageKindName(kind) stringByAppendingString:@"|"];
    NSUInteger n = 0;
    for (NSString *stable in gBoolOverrides.allKeys) if ([stable hasPrefix:prefix]) n++;
    return n;
}

NSString *FBGRBoolRuntimeDiagnostic(FBGRBoolRuntimeImageKind kind) {
    NSArray *c = FBGRBoolRuntimeCandidates(kind, NO);
    return [NSString stringWithFormat:@"%@\ncandidates=%lu\noverrides=%lu\nhooksInstalled=%lu\nsource=objc runtime class_getImageName + BOOL/no-arg method scan",
        FBGRBoolRuntimeImageTitle(kind), (unsigned long)c.count,
        (unsigned long)FBGRBoolRuntimeOverrideCountForImageKind(kind),
        (unsigned long)gBoolHookCount];
}
