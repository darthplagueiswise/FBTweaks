#import "FBGRBoolRuntimeInventory.h"
#import "../FBGramPrefix.h"
#import "FBGRLog.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <string.h>

static NSString *const kFBGRBoolOverridesKey = @"fbgr.runtime.bool.overrides.v3";
static NSString *const kFBGRBoolLegacyOverridesKey = @"fbgr.runtime.bool.overrides.v2";

@implementation FBGRBoolRuntimeItem
@end

static NSMutableDictionary<NSString *, NSValue *> *gOriginalIMPs;
static NSMutableSet<NSString *> *gHookedNames;
static NSUInteger gScanN = 0;
static __thread BOOL gBoolGuard = NO;

static NSString *FBGRRuntimeBoolKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%c%@#%@", classMethod ? '+' : '-', className ?: @"", selectorName ?: @""];
}

static BOOL FBGRSplitRuntimeBoolKey(NSString *name, NSString **className, NSString **selectorName, BOOL *classMethod) {
    if (name.length < 4) return NO;
    unichar prefix = [name characterAtIndex:0];
    if (prefix != '+' && prefix != '-') return NO;
    NSRange r = [name rangeOfString:@"#"];
    if (r.location == NSNotFound || r.location <= 1 || NSMaxRange(r) >= name.length) return NO;
    if (className) *className = [name substringWithRange:NSMakeRange(1, r.location - 1)];
    if (selectorName) *selectorName = [name substringFromIndex:NSMaxRange(r)];
    if (classMethod) *classMethod = (prefix == '+');
    return YES;
}

static NSDictionary *FBGRBoolOverridesDict(void) {
    NSDictionary *d = [FBGRPrefs() dictionaryForKey:kFBGRBoolOverridesKey];
    if ([d isKindOfClass:NSDictionary.class]) return d;
    NSDictionary *legacy = [FBGRPrefs() dictionaryForKey:kFBGRBoolLegacyOverridesKey];
    return [legacy isKindOfClass:NSDictionary.class] ? legacy : @{};
}

static NSMutableDictionary *FBGRBoolOverridesMutable(void) {
    return [FBGRBoolOverridesDict() mutableCopy] ?: [NSMutableDictionary dictionary];
}

static NSNumber *FBGRBoolOverrideStateForKey(NSString *key) {
    id v = FBGRBoolOverridesDict()[key];
    return [v respondsToSelector:@selector(boolValue)] ? @([v boolValue]) : nil;
}

static NSNumber *FBGRBoolOverrideState(NSString *className, NSString *selectorName, BOOL classMethod) {
    return FBGRBoolOverrideStateForKey(FBGRRuntimeBoolKey(className, selectorName, classMethod));
}

static BOOL FBGRReturnIsBool(Method m) {
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char ret[16] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    return ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C';
}

static BOOL FBGRSelectorAllowed(NSString *sel) {
    if (!sel.length || [sel containsString:@":"]) return NO;
    NSString *s = sel.lowercaseString;
    if ([s hasPrefix:@"set"]) return NO;
    if ([s isEqualToString:@"hash"] || [s isEqualToString:@"isproxy"] || [s isEqualToString:@"respondstoselector"]) return NO;
    return ([s hasPrefix:@"is"] || [s hasPrefix:@"has"] || [s hasPrefix:@"can"] || [s hasPrefix:@"should"] ||
            [s hasPrefix:@"allow"] || [s hasPrefix:@"use"] || [s containsString:@"enabled"] ||
            [s containsString:@"debug"] || [s containsString:@"dogfood"] || [s containsString:@"internal"] ||
            [s containsString:@"experiment"] || [s containsString:@"liquid"] || [s containsString:@"glass"] ||
            [s containsString:@"tab"] || [s containsString:@"gate"] || [s containsString:@"gating"] ||
            [s containsString:@"feature"] || [s containsString:@"stories"] || [s containsString:@"story"]);
}

static NSString *FBGRImagePathForKind(FBGRBoolRuntimeImageKind kind) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (kind == FBGRBoolRuntimeImageKindExecutable) {
            if (strstr(name, "/Facebook.app/Facebook") && !strstr(name, ".dylib")) return [NSString stringWithUTF8String:name];
        } else {
            if (strstr(name, "/FBSharedFramework.framework/FBSharedFramework")) return [NSString stringWithUTF8String:name];
        }
    }
    return nil;
}

static void FBGRAppendMethods(Class cls, BOOL classMethod, NSString *img, NSMutableArray *out) {
    Class target = classMethod ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = target ? class_copyMethodList(target, &count) : NULL;
    if (!methods) return;
    for (unsigned int i = 0; i < count; i++) {
        Method m = methods[i];
        if (!FBGRReturnIsBool(m)) continue;
        SEL sel = method_getName(m);
        NSString *selName = NSStringFromSelector(sel);
        if (!FBGRSelectorAllowed(selName)) continue;
        FBGRBoolRuntimeItem *item = [FBGRBoolRuntimeItem new];
        item.className = NSStringFromClass(cls);
        item.selectorName = selName;
        item.imageName = img ?: @"";
        item.classMethod = classMethod;
        NSNumber *ov = FBGRBoolOverrideState(item.className, item.selectorName, item.classMethod);
        item.overrideSet = (ov != nil);
        item.overrideValue = ov.boolValue;
        item.hooked = [gHookedNames containsObject:FBGRRuntimeBoolKey(item.className, item.selectorName, item.classMethod)];
        [out addObject:item];
    }
    free(methods);
}

@implementation FBGRBoolRuntimeInventory

+ (NSArray<FBGRBoolRuntimeItem *> *)scanImageKind:(FBGRBoolRuntimeImageKind)kind {
    NSMutableArray *out = [NSMutableArray array];
    NSString *imagePath = FBGRImagePathForKind(kind);
    unsigned int classCount = 0;
    const char **classNames = imagePath.length ? objc_copyClassNamesForImage(imagePath.UTF8String, &classCount) : NULL;
    if (classNames) {
        for (unsigned int i = 0; i < classCount; i++) {
            const char *cname = classNames[i];
            if (!cname) continue;
            Class cls = objc_getClass(cname);
            if (!cls) continue;
            FBGRAppendMethods(cls, NO, imagePath, out);
            FBGRAppendMethods(cls, YES, imagePath, out);
        }
        free(classNames);
    }
    [out sortUsingComparator:^NSComparisonResult(FBGRBoolRuntimeItem *a, FBGRBoolRuntimeItem *b) {
        NSComparisonResult r = [a.className caseInsensitiveCompare:b.className];
        return r == NSOrderedSame ? [a.selectorName caseInsensitiveCompare:b.selectorName] : r;
    }];
    gScanN += out.count;
    return out;
}

+ (void)installHookForItem:(FBGRBoolRuntimeItem *)item {
    if (!item.className.length || !item.selectorName.length) return;
    NSString *key = FBGRRuntimeBoolKey(item.className, item.selectorName, item.classMethod);
    @synchronized (self) {
        if ([gHookedNames containsObject:key]) { item.hooked = YES; return; }
    }

    Class cls = objc_getClass(item.className.UTF8String);
    SEL sel = NSSelectorFromString(item.selectorName);
    if (!cls || !sel) return;
    Method m = item.classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!FBGRReturnIsBool(m)) return;

    NSString *className = [item.className copy];
    NSString *selectorName = [item.selectorName copy];
    BOOL isClassMethod = item.classMethod;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver) {
        NSString *runtimeKey = FBGRRuntimeBoolKey(className, selectorName, isClassMethod);
        NSNumber *forced = FBGRBoolOverrideStateForKey(runtimeKey);
        if (forced) return forced.boolValue;
        IMP orig = NULL;
        @synchronized ([FBGRBoolRuntimeInventory class]) { orig = [[gOriginalIMPs objectForKey:runtimeKey] pointerValue]; }
        if (!orig || gBoolGuard) return NO;
        gBoolGuard = YES;
        BOOL out = ((BOOL (*)(id, SEL))orig)(receiver, sel);
        gBoolGuard = NO;
        return out;
    });

    IMP originalIMP = method_setImplementation(m, replacement);
    @synchronized (self) {
        if (!gOriginalIMPs) gOriginalIMPs = [NSMutableDictionary dictionary];
        if (!gHookedNames) gHookedNames = [NSMutableSet set];
        if (originalIMP) gOriginalIMPs[key] = [NSValue valueWithPointer:originalIMP];
        [gHookedNames addObject:key];
    }
    item.hooked = YES;
    FBGRLogAppend([NSString stringWithFormat:@"Bool hook installed %@", key]);
}

+ (void)setOverrideForItem:(FBGRBoolRuntimeItem *)item value:(BOOL)value {
    NSString *key = FBGRRuntimeBoolKey(item.className, item.selectorName, item.classMethod);

    [self installHookForItem:item];

    NSMutableDictionary *d = FBGRBoolOverridesMutable();
    d[key] = @(value);
    [FBGRPrefs() setObject:d forKey:kFBGRBoolOverridesKey];
    [FBGRPrefs() removeObjectForKey:kFBGRBoolLegacyOverridesKey];
    [FBGRPrefs() synchronize];

    item.overrideSet = YES;
    item.overrideValue = value;

    @synchronized (self) {
        item.hooked = [gHookedNames containsObject:key];
    }
}

+ (void)clearOverrideForItem:(FBGRBoolRuntimeItem *)item {
    NSMutableDictionary *d = FBGRBoolOverridesMutable();
    [d removeObjectForKey:FBGRRuntimeBoolKey(item.className, item.selectorName, item.classMethod)];
    [FBGRPrefs() setObject:d forKey:kFBGRBoolOverridesKey];
    [FBGRPrefs() removeObjectForKey:kFBGRBoolLegacyOverridesKey];
    [FBGRPrefs() synchronize];
    item.overrideSet = NO;
}

+ (void)installPersistedOverrideHooks {
    NSDictionary *d = FBGRBoolOverridesDict();
    if (![d isKindOfClass:NSDictionary.class] || d.count == 0) return;
    for (NSString *key in d) {
        NSString *cls = nil, *sel = nil; BOOL classMethod = NO;
        if (!FBGRSplitRuntimeBoolKey(key, &cls, &sel, &classMethod)) continue;
        FBGRBoolRuntimeItem *item = [FBGRBoolRuntimeItem new];
        item.className = cls;
        item.selectorName = sel;
        item.classMethod = classMethod;
        [self installHookForItem:item];
    }
}

+ (void)clearAllOverrides {
    [FBGRPrefs() removeObjectForKey:kFBGRBoolOverridesKey];
    [FBGRPrefs() removeObjectForKey:kFBGRBoolLegacyOverridesKey];
    [FBGRPrefs() synchronize];
}

+ (NSString *)diagnostic {
    return [NSString stringWithFormat:@"bool runtime hooks=%lu\nscan rows=%lu\noverrides=%lu\nstrategy=objc_copyClassNamesForImage + method_setImplementation exact owner", (unsigned long)gHookedNames.count, (unsigned long)gScanN, (unsigned long)FBGRBoolOverridesDict().count];
}
@end
