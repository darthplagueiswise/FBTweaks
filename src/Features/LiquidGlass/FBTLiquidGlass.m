#import "FBTPrefix.h"
#import "FBTDefaults.h"
#include "../../../modules/fishhook/fishhook.h"

// =====================================================================
// Liquid Glass
// _METAIsLiquidGlassEnabled é IMPORTADA pelo executável Facebook
// (confirmado em Facebook_imports.txt) -> fishhook reescreve o GOT slot.
// Flag latched no ctor; alternar exige restart.
// =====================================================================

static BOOL sFBTForceLiquidGlass = NO;
static BOOL (*orig_METAIsLiquidGlassEnabled)(void) = NULL;

static BOOL fbt_METAIsLiquidGlassEnabled(void) {
    if (sFBTForceLiquidGlass) return YES;
    return orig_METAIsLiquidGlassEnabled ? orig_METAIsLiquidGlassEnabled() : NO;
}

// Chamado pelo Tweak.x SOMENTE se a pref estiver on no launch.
void FBTInstallLiquidGlassHooks(void) {
    sFBTForceLiquidGlass = YES; // latched: já validamos a pref no ctor
    struct rebinding r = {
        "METAIsLiquidGlassEnabled",
        (void *)fbt_METAIsLiquidGlassEnabled,
        (void **)&orig_METAIsLiquidGlassEnabled
    };
    rebind_symbols(&r, 1);
    FBTLog(@"LiquidGlass fishhook instalado");
}
