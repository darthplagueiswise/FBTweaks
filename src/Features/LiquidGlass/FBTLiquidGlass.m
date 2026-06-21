#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import "Runtime/FBTRuntimeBoolBrowser.h"
#import <dlfcn.h>
#include "../../../modules/fishhook/fishhook.h"

// =====================================================================
// Liquid Glass
// _METAIsLiquidGlassEnabled é IMPORTADA pelo executável Facebook
// (confirmado em Facebook_imports.txt) -> fishhook reescreve o GOT slot.
// Flag latched no ctor; alternar exige restart.
// =====================================================================

static BOOL sFBTForceLiquidGlass = NO;
static BOOL (*orig_METAIsLiquidGlassEnabled)(void) = NULL;
static BOOL (*orig_IGLiquidGlassNavigationExperiment_isEnabled)(void) = NULL;
static BOOL (*orig_IGThrowbackChromeExperiment_isEnabled)(void) = NULL;

static BOOL fbt_METAIsLiquidGlassEnabled(void) {
    if (sFBTForceLiquidGlass) return YES;
    return orig_METAIsLiquidGlassEnabled ? orig_METAIsLiquidGlassEnabled() : NO;
}

static BOOL fbt_AlwaysYES(void) { return YES; }

static BOOL FBTHookDirectBoolIfExists(const char *name, void *replacement, void **orig) {
    // v3.1: disabled for sideload safety. Direct C function patching in
    // FBSharedFramework __TEXT caused CODESIGNING / Invalid Page. LiquidGlass
    // now uses fishhook for imported C symbols plus Runtime BOOL Browser for
    // ObjC/Swift-dispatch getters.
    (void)name; (void)replacement; (void)orig;
    return NO;
}

static void FBTInstallLiquidGlassRuntimeBoolHooks(void) {
    NSArray<NSString *> *queries = @[
        @"LiquidGlass",
        @"isLiquidGlassEnabled",
        @"_isLiquidGlassEnabled",
        @"IGLiquidGlass",
        @"GlassExperimentHelper"
    ];
    NSUInteger installed = 0;
    for (NSString *q in queries) {
        NSArray<NSDictionary *> *hits = FBTRuntimeBoolSearch(q, 250);
        for (NSDictionary *hit in hits) {
            NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", hit[@"class"] ?: @"", hit[@"selector"] ?: @"", hit[@"imageKind"] ?: @""] lowercaseString];
            if (![hay containsString:@"liquidglass"] && ![hay containsString:@"glass"]) continue;
            NSString *sel = [hit[@"selector"] lowercaseString] ?: @"";
            if (!([sel containsString:@"enabled"] || [sel isEqualToString:@"isenabled"] || [sel containsString:@"canuse"])) continue;
            FBTRuntimeBoolSetOverride(hit, YES);
            installed++;
            if (installed >= 80) return;
        }
    }
}

// Chamado pelo Tweak.x quando a pref estiver on. v3 tenta três caminhos:
// 1) C importado por fishhook, se existir nesse build;
// 2) runtime BOOL ObjC/Swift-dispatch em classes LiquidGlass carregadas.
// Direct C/Swift symbol patching is disabled on sideload because it dirties signed __TEXT.
void FBTInstallLiquidGlassHooks(void) {
    sFBTForceLiquidGlass = YES;

    struct rebinding r = {
        "METAIsLiquidGlassEnabled",
        (void *)fbt_METAIsLiquidGlassEnabled,
        (void **)&orig_METAIsLiquidGlassEnabled
    };
    rebind_symbols(&r, 1);

    FBTInstallLiquidGlassRuntimeBoolHooks();
    FBTLog(@"LiquidGlass hooks instalados");
}
