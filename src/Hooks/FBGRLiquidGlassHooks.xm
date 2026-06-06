#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"
#import "../FBGramPrefix.h"

typedef BOOL (*BoolIMP)(id, SEL);
typedef struct { Class cls; SEL sel; IMP orig; } FBGRLGHook;
static FBGRLGHook gHooks[96];
static NSUInteger gHookN = 0;
static BOOL gInstalled = NO;
static NSString * const kFBGRLiquidGlassForcedKey = @"fbgr.liquidglass.force";

static IMP FBGRLGOrig(Class cls, SEL sel) {
    for (NSUInteger i = 0; i < gHookN; i++) if (gHooks[i].cls == cls && gHooks[i].sel == sel) return gHooks[i].orig;
    return NULL;
}

static BOOL FBGRLGForced(void) { return [FBGRPrefs() boolForKey:kFBGRLiquidGlassForcedKey]; }

static BOOL FBGRSelectorIsNegative(SEL sel) {
    NSString *s = NSStringFromSelector(sel).lowercaseString ?: @"";
    return [s containsString:@"disabled"] || [s containsString:@"disable"] || [s containsString:@"blur"];
}

static BOOL h_bool(id self, SEL _cmd) {
    if (FBGRLGForced()) return FBGRSelectorIsNegative(_cmd) ? NO : YES;
    IMP orig = FBGRLGOrig(object_getClass(self), _cmd);
    if (!orig) orig = FBGRLGOrig([self class], _cmd);
    return orig ? ((BoolIMP)orig)(self, _cmd) : NO;
}

static void HookOne(Class cls, SEL sel, BOOL meta) {
    if (!cls || !sel || gHookN >= 96) return;
    Method m = meta ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m || method_getNumberOfArguments(m) != 2) return;
    char *ret = method_copyReturnType(m);
    BOOL ok = ret && (ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C');
    if (ret) free(ret);
    if (!ok) return;
    Class hookCls = meta ? object_getClass(cls) : cls;
    for (NSUInteger i = 0; i < gHookN; i++) if (gHooks[i].cls == hookCls && gHooks[i].sel == sel) return;
    IMP orig = NULL;
    MSHookMessageEx(hookCls, sel, (IMP)h_bool, &orig);
    if (orig) gHooks[gHookN++] = (FBGRLGHook){hookCls, sel, orig};
}

static void HookClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) return;
    SEL sels[] = {
        sel_registerName("isEnabled"),
        sel_registerName("isHomeFeedHeaderEnabled"),
        sel_registerName("isGlassRenderingOptimizationEnabled"),
        sel_registerName("isProfileSegmentedTabsGlassDisabled"),
        sel_registerName("isLegibilityBlurEnabled"),
        sel_registerName("navBarIsLiquidGlassEnabled"),
        sel_registerName("isMediaLiquidGlassEnabled"),
        sel_registerName("isGlassChatbarUXActive"),
        sel_registerName("isContextMenuGlassEffectEnabled"),
        sel_registerName("_isGlassEffectEnabled"),
    };
    for (NSUInteger i = 0; i < sizeof(sels)/sizeof(sels[0]); i++) { HookOne(cls, sels[i], NO); HookOne(cls, sels[i], YES); }
}

static void FBGRLiquidGlassApplyMCSlots(BOOL forced) {
    uint64_t slots[] = {3406, 3426, 4470, 1489};
    for (NSUInteger i = 0; i < sizeof(slots)/sizeof(slots[0]); i++) forced ? FBGRGateSet(slots[i], YES) : FBGRGateClear(slots[i]);
}

extern "C" void FBGRLiquidGlassEnsureInstalled(void) {
    // Explicit toggle can install immediately. Restart reapply is delayed until app startup.
    HookClass(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper");
    HookClass(@"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper");
    HookClass(@"MSGThreadViewController");
    gInstalled = YES;
    FBGRLogAppend([NSString stringWithFormat:@"LiquidGlass hooks installed=%lu forced=%@", (unsigned long)gHookN, FBGRLGForced()?@"YES":@"NO"]);
}

extern "C" void FBGRLiquidGlassSetForced(BOOL forced) {
    [FBGRPrefs() setBool:forced forKey:kFBGRLiquidGlassForcedKey];
    [FBGRPrefs() synchronize];
    FBGRLiquidGlassApplyMCSlots(forced);
    if (forced) FBGRLiquidGlassEnsureInstalled();
}

extern "C" NSString *FBGRLiquidGlassDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\nhooks=%lu\nforced=%@\nmcSlots=3406,3426,4470,1489\nstartup=delayed", gInstalled?@"YES":@"NO", (unsigned long)gHookN, FBGRLGForced()?@"YES":@"NO"];
}

static void FBGRLiquidGlassStartupPass(void) {
    if (!FBGRLGForced()) return;
    FBGRLiquidGlassApplyMCSlots(YES);
    FBGRLiquidGlassEnsureInstalled();
}

__attribute__((constructor))
static void FBGRLiquidGlassCtor(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidFinishLaunchingNotification" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) { FBGRLiquidGlassStartupPass(); }];
        dispatch_async(dispatch_get_main_queue(), ^{ FBGRLiquidGlassStartupPass(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ FBGRLiquidGlassStartupPass(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ FBGRLiquidGlassStartupPass(); });
    }
}
