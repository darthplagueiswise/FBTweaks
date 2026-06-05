// FBGRLiquidGlassHooks.xm — no fake slot-0 LiquidGlass flag.
// Visual LiquidGlass for the menu is handled by FBGRMenuTheme using real UIKit glass classes only.
#import <Foundation/Foundation.h>
#import "../FBGramPrefix.h"
static BOOL gChecked = NO;
extern "C" void FBGRLiquidGlassEnsureInstalled(void) { gChecked = YES; FBGRLogHook("LG", "no fake MC LiquidGlass slot; UI uses real UIKit glass if runtime exposes it"); }
extern "C" BOOL FBGRLiquidGlassIsHooked(void) { return gChecked; }
