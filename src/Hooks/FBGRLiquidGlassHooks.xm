// FBGRLiquidGlassHooks.xm — fishhook _METAIsLiquidGlassEnabled
#import <Foundation/Foundation.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../../modules/fishhook/fishhook.h"

typedef BOOL (*LGFn)(void);
static LGFn orig_METAIsLG = NULL;
static BOOL gInstalled = NO;

static BOOL h_METAIsLiquidGlassEnabled(void) {
    if (FBGRPref(kFBGRLiquidGlassMaster)) return YES;
    return orig_METAIsLG ? orig_METAIsLG() : NO;
}

extern "C" void FBGRLiquidGlassEnsureInstalled(void) {
    if (gInstalled) return;
    struct rebinding rb = { "METAIsLiquidGlassEnabled", (void*)h_METAIsLiquidGlassEnabled, (void**)&orig_METAIsLG };
    int r = rebind_symbols(&rb, 1);
    gInstalled = (r == 0 && orig_METAIsLG != NULL);
    FBGRLogHook("LG", "fishhook=%d hooked=%@", r, gInstalled?@"YES":@"NO");
}
extern "C" BOOL FBGRLiquidGlassIsHooked(void) { return gInstalled; }

__attribute__((constructor))
static void ctor(void) { @autoreleasepool { FBGRLiquidGlassEnsureInstalled(); } }
