#import "FBGRBoolRuntimeInventory.h"
#import "../FBGramPrefix.h"
#import "FBGRLog.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>

@implementation FBGRBoolRuntimeItem
@end

typedef BOOL (*BoolNoArgIMP)(id, SEL);
typedef struct { Class cls; SEL sel; BOOL classMethod; IMP orig; BOOL overrideSet; BOOL overrideValue; char key[512]; } FBGRBoolHook;
#define FBGR_BOOL_MAX 2048
static FBGRBoolHook gHooks[FBGR_BOOL_MAX];
static NSUInteger gHookN = 0;
static NSUInteger gScanN = 0;

static NSString *FBGRKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"fbgr.bool.%@.%@.%@", classMethod?@"+":@"-", className ?: @"", selectorName ?: @""];
}

static FBGRBoolHook *FBGRFindHook(Class cls, SEL sel, BOOL classMethod) {
    for (NSUInteger i=0;i<gHookN;i++) if (gHooks[i].cls == cls && gHooks[i].sel == sel && gHooks[i].classMethod == classMethod) return &gHooks[i];
    return NULL;
}

static BOOL h_bool(id self, SEL _cmd) {
    Class cls = object_getClass(self);
    FBGRBoolHook *e = FBGRFindHook(cls, _cmd, YES);
    if (!e) e = FBGRFindHook([self class], _cmd, NO);
    if (e && e->overrideSet) return e->overrideValue;
    return (e && e->orig) ? ((BoolNoArgIMP)e->orig)(self, _cmd) : NO;
}

static BOOL FBGRReturnIsBool(const char *ret) {
    if (!ret || !ret[0]) return NO;
    return ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C';
}

static BOOL FBGRSelectorAllowed(NSString *sel) {
    if (!sel.length || [sel containsString:@":"]) return NO;
    NSString *s = sel.lowercaseString;
    if ([s hasPrefix:@"set"]) return NO;
    if ([s isEqualToString:@"hash"] || [s isEqualToString:@"isproxy"] || [s isEqualToString:@"retain"] || [s isEqualToString:@"release"]) return NO;
    return ([s hasPrefix:@"is"] || [s hasPrefix:@"has"] || [s hasPrefix:@"can"] || [s hasPrefix:@"should"] || [s hasPrefix:@"allows"] || [s containsString:@"enabled"] || [s containsString:@"debug"] || [s containsString:@"dogfood"] || [s containsString:@"internal"] || [s containsString:@"experiment"] || [s containsString:@"liquid"] || [s containsString:@"glass"] || [s containsString:@"tab"]);
}

static BOOL FBGRImageMatches(const char *img, FBGRBoolRuntimeImageKind kind) {
    if (!img) return NO;
    NSString *s = [NSString stringWithUTF8String:img] ?: @"";
    if (kind == FBGRBoolRuntimeImageKindExecutable) return [s containsString:@"/Facebook.app/Facebook"];
    return [s containsString:@"/FBSharedFramework.framework/FBSharedFramework"];
}

static void FBGRAddMethods(NSMutableArray *out, Class cls, BOOL classMethod, NSString *img) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(classMethod ? object_getClass(cls) : cls, &count);
    for (unsigned int i=0;i<count;i++) {
        Method m = methods[i];
        if (method_getNumberOfArguments(m) != 2) continue;
        char *ret = method_copyReturnType(m);
        BOOL ok = FBGRReturnIsBool(ret);
        if (ret) free(ret);
        if (!ok) continue;
        SEL sel = method_getName(m);
        NSString *selName = NSStringFromSelector(sel);
        if (!FBGRSelectorAllowed(selName)) continue;
        FBGRBoolRuntimeItem *item = [FBGRBoolRuntimeItem new];
        item.className = NSStringFromClass(cls);
        item.selectorName = selName;
        item.imageName = img;
        item.classMethod = classMethod;
        NSString *key = FBGRKey(item.className, item.selectorName, item.classMethod);
        id obj = [FBGRPrefs() objectForKey:key];
        item.overrideSet = obj != nil;
        item.overrideValue = [obj boolValue];
        Class hookCls = classMethod ? object_getClass(cls) : cls;
        item.hooked = FBGRFindHook(hookCls, sel, classMethod) != NULL;
        [out addObject:item];
    }
    if (methods) free(methods);
}

@implementation FBGRBoolRuntimeInventory

+ (NSArray<FBGRBoolRuntimeItem *> *)scanImageKind:(FBGRBoolRuntimeImageKind)kind {
    int n = objc_getClassList(NULL, 0);
    if (n <= 0) return @[];
    Class *classes = (Class *)calloc((NSUInteger)n, sizeof(Class));
    n = objc_getClassList(classes, n);
    NSMutableArray *out = [NSMutableArray array];
    for (int i=0;i<n;i++) {
        Class cls = classes[i];
        const char *imgC = class_getImageName(cls);
        if (!FBGRImageMatches(imgC, kind)) continue;
        NSString *img = imgC ? [NSString stringWithUTF8String:imgC] : @"";
        FBGRAddMethods(out, cls, NO, img);
        FBGRAddMethods(out, cls, YES, img);
    }
    free(classes);
    [out sortUsingComparator:^NSComparisonResult(FBGRBoolRuntimeItem *a, FBGRBoolRuntimeItem *b) {
        NSComparisonResult r = [a.className compare:b.className];
        return r == NSOrderedSame ? [a.selectorName compare:b.selectorName] : r;
    }];
    gScanN += out.count;
    return out;
}

+ (void)installHookForItem:(FBGRBoolRuntimeItem *)item {
    if (!item.className.length || !item.selectorName.length || gHookN >= FBGR_BOOL_MAX) return;
    Class cls = NSClassFromString(item.className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(item.selectorName);
    Class hookCls = item.classMethod ? object_getClass(cls) : cls;
    if (FBGRFindHook(hookCls, sel, item.classMethod)) return;
    Method m = item.classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m || method_getNumberOfArguments(m) != 2) return;
    IMP orig = NULL;
    MSHookMessageEx(hookCls, sel, (IMP)h_bool, &orig);
    if (!orig) return;
    FBGRBoolHook *e = &gHooks[gHookN++];
    memset(e, 0, sizeof(*e));
    e->cls = hookCls; e->sel = sel; e->classMethod = item.classMethod; e->orig = orig;
    NSString *key = FBGRKey(item.className, item.selectorName, item.classMethod);
    strlcpy(e->key, key.UTF8String, sizeof(e->key));
    id obj = [FBGRPrefs() objectForKey:key];
    e->overrideSet = obj != nil; e->overrideValue = [obj boolValue];
}

+ (void)setOverrideForItem:(FBGRBoolRuntimeItem *)item value:(BOOL)value {
    [self installHookForItem:item];
    NSString *key = FBGRKey(item.className, item.selectorName, item.classMethod);
    [FBGRPrefs() setBool:value forKey:key]; [FBGRPrefs() synchronize];
    Class cls = NSClassFromString(item.className);
    FBGRBoolHook *e = cls ? FBGRFindHook(item.classMethod ? object_getClass(cls) : cls, NSSelectorFromString(item.selectorName), item.classMethod) : NULL;
    if (e) { e->overrideSet = YES; e->overrideValue = value; }
    item.overrideSet = YES; item.overrideValue = value; item.hooked = YES;
}

+ (void)clearOverrideForItem:(FBGRBoolRuntimeItem *)item {
    NSString *key = FBGRKey(item.className, item.selectorName, item.classMethod);
    [FBGRPrefs() removeObjectForKey:key]; [FBGRPrefs() synchronize];
    Class cls = NSClassFromString(item.className);
    FBGRBoolHook *e = cls ? FBGRFindHook(item.classMethod ? object_getClass(cls) : cls, NSSelectorFromString(item.selectorName), item.classMethod) : NULL;
    if (e) e->overrideSet = NO;
    item.overrideSet = NO;
}

+ (NSString *)diagnostic { return [NSString stringWithFormat:@"hooked=%lu\nscanRows=%lu", (unsigned long)gHookN, (unsigned long)gScanN]; }
@end
