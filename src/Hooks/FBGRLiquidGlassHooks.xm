#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../Runtime/FBGRLog.h"

typedef BOOL (*BoolIMP)(id, SEL);
typedef struct { Class cls; SEL sel; IMP orig; } FBGRLGHook;
#define FBGR_LG_MAX 80
static FBGRLGHook gHooks[FBGR_LG_MAX];
static NSUInteger gHookN = 0;
static BOOL gInstalled = NO;
static BOOL gForce = NO;

static IMP FBGRLGOrig(Class cls, SEL sel) {
    for (NSUInteger i = 0; i < gHookN; i++) if (gHooks[i].cls == cls && gHooks[i].sel == sel) return gHooks[i].orig;
    return NULL;
}

static BOOL h_bool(id self, SEL _cmd) {
    if (gForce) return YES;
    IMP orig = FBGRLGOrig(object_getClass(self), _cmd);
    if (!orig) orig = FBGRLGOrig([self class], _cmd);
    return orig ? ((BoolIMP)orig)(self, _cmd) : NO;
}

static void HookOne(Class cls, SEL sel, BOOL meta) {
    if (!cls || !sel || gHookN >= FBGR_LG_MAX) return;
    Method m = meta ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m) return;
    Class hookCls = meta ? object_getClass(cls) : cls;
    for (NSUInteger i = 0; i < gHookN; i++) if (gHooks[i].cls == hookCls && gHooks[i].sel == sel) return;
    IMP orig = NULL;
    MSHookMessageEx(hookCls, sel, (IMP)h_bool, &orig);
    if (orig) gHooks[gHookN++] = (FBGRLGHook){ hookCls, sel, orig };
}

static void HookClass(NSString *name) {
    Class cls = NSClassFromString(name);
    SEL sels[] = {
        sel_registerName("isEnabled"),
        sel_registerName("isHomeFeedHeaderEnabled"),
        sel_registerName("isGlassRenderingOptimizationEnabled"),
        sel_registerName("isLegibilityBlurEnabled"),
        sel_registerName("isLiquidGlassEnabled")
    };
    for (NSUInteger i = 0; i < sizeof(sels)/sizeof(sels[0]); i++) { HookOne(cls, sels[i], NO); HookOne(cls, sels[i], YES); }
}

extern "C" void FBGRLiquidGlassEnsureInstalled(void) {
    if (gInstalled) return;
    HookClass(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper");
    HookClass(@"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper");
    gInstalled = YES;
    FBGRLogAppend([NSString stringWithFormat:@"LiquidGlass hooks installed=%lu", (unsigned long)gHookN]);
}

extern "C" void FBGRLiquidGlassSetForced(BOOL forced) {
    gForce = forced;
    if (forced) FBGRLiquidGlassEnsureInstalled();
}

extern "C" NSString *FBGRLiquidGlassDiagnostic(void) {
    return [NSString stringWithFormat:@"installed=%@\nhooks=%lu\nforced=%@", gInstalled ? @"YES" : @"NO", (unsigned long)gHookN, gForce ? @"YES" : @"NO"];
}
