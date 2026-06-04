// FBGRLiquidGlassHooks.xm — SDK26 LiquidGlass hooks.
// Validated surfaces in FBSharedFramework 106:
//   _TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper
//   _TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper
// Also keeps METAIsLiquidGlassEnabled fishhook as fallback for older builds.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../../modules/fishhook/fishhook.h"

typedef BOOL (*BoolIMP)(id, SEL);
typedef BOOL (*LGFn)(void);

static LGFn orig_METAIsLG = NULL;
static BOOL gFishhookInstalled = NO;
static BOOL gObjCHooksInstalled = NO;
static NSUInteger gObjCHookCount = 0;

typedef struct { Class cls; SEL sel; IMP orig; } FBGRLGHook;
#define FBGR_LG_MAX 64
static FBGRLGHook gLGHooks[FBGR_LG_MAX];
static int gLGHookN = 0;

static BOOL FBGRLGShouldForce(void) { return FBGRPref(kFBGRLiquidGlassMaster); }

static IMP FBGRLGOrig(Class cls, SEL sel) {
    for (int i = 0; i < gLGHookN; i++) if (gLGHooks[i].cls == cls && gLGHooks[i].sel == sel) return gLGHooks[i].orig;
    return NULL;
}

static BOOL h_METAIsLiquidGlassEnabled(void) {
    if (FBGRLGShouldForce()) return YES;
    return orig_METAIsLG ? orig_METAIsLG() : NO;
}

static BOOL h_lgBool(id self, SEL _cmd) {
    if (FBGRLGShouldForce()) return YES;
    IMP orig = FBGRLGOrig(object_getClass(self), _cmd);
    if (!orig) orig = FBGRLGOrig([self class], _cmd);
    return orig ? ((BoolIMP)orig)(self, _cmd) : NO;
}

static void FBGRLGHookOne(Class cls, SEL sel, BOOL classMethod) {
    if (!cls || !sel || gLGHookN >= FBGR_LG_MAX) return;
    Method m = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m) return;
    Class hookClass = classMethod ? object_getClass(cls) : cls;
    for (int i = 0; i < gLGHookN; i++) if (gLGHooks[i].cls == hookClass && gLGHooks[i].sel == sel) return;
    IMP orig = NULL;
    MSHookMessageEx(hookClass, sel, (IMP)h_lgBool, &orig);
    if (orig) {
        gLGHooks[gLGHookN].cls = hookClass;
        gLGHooks[gLGHookN].sel = sel;
        gLGHooks[gLGHookN].orig = orig;
        gLGHookN++;
        gObjCHookCount++;
    }
}

static void FBGRLGHookClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) return;
    SEL sels[] = {
        sel_registerName("isEnabled"),
        sel_registerName("isHomeFeedHeaderEnabled"),
        sel_registerName("isGlassRenderingOptimizationEnabled"),
        sel_registerName("isLegibilityBlurEnabled"),
        sel_registerName("isLiquidGlassEnabled"),
    };
    const unsigned long n = sizeof(sels) / sizeof(sels[0]);
    for (unsigned long i = 0; i < n; i++) {
        FBGRLGHookOne(cls, sels[i], NO);
        FBGRLGHookOne(cls, sels[i], YES);
    }
}

extern "C" void FBGRLiquidGlassEnsureInstalled(void) {
    if (!gFishhookInstalled) {
        struct rebinding rbs[] = {
            { "METAIsLiquidGlassEnabled", (void *)h_METAIsLiquidGlassEnabled, (void **)&orig_METAIsLG },
            { "_METAIsLiquidGlassEnabled", (void *)h_METAIsLiquidGlassEnabled, (void **)&orig_METAIsLG },
        };
        int r = rebind_symbols(rbs, 2);
        gFishhookInstalled = (r == 0 && orig_METAIsLG != NULL);
    }

    FBGRLGHookClass(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper");
    FBGRLGHookClass(@"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper");
    gObjCHooksInstalled = (gObjCHookCount > 0);
    FBGRLogHook("LG", "fishhook=%@ objcHooks=%lu", gFishhookInstalled ? @"YES" : @"NO", (unsigned long)gObjCHookCount);
}

extern "C" BOOL FBGRLiquidGlassIsHooked(void) { return gFishhookInstalled || gObjCHooksInstalled; }
extern "C" NSString *FBGRLiquidGlassDiagnostic(void) {
    return [NSString stringWithFormat:@"fishhook=%@\nobjcHooks=%lu\nclasses=IGLiquidGlassExperimentHelper\nmasterPref=%@",
        gFishhookInstalled ? @"YES" : @"NO", (unsigned long)gObjCHookCount, FBGRLGShouldForce() ? @"ON" : @"OFF"];
}
