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
    void *sym = dlsym(RTLD_DEFAULT, name);
    if (!sym) return NO;
    MSHookFunction(sym, replacement, orig);
    FBTLog(@"LiquidGlass direct hook instalado: %s", name);
    return YES;
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
// 2) Swift/C exports diretos conhecidos via MSHookFunction;
// 3) runtime BOOL ObjC/Swift-dispatch em classes LiquidGlass carregadas.
void FBTInstallLiquidGlassHooks(void) {
    sFBTForceLiquidGlass = YES;

    struct rebinding r = {
        "METAIsLiquidGlassEnabled",
        (void *)fbt_METAIsLiquidGlassEnabled,
        (void **)&orig_METAIsLiquidGlassEnabled
    };
    rebind_symbols(&r, 1);

    FBTHookDirectBoolIfExists("METAIsLiquidGlassEnabled",
                              (void *)fbt_METAIsLiquidGlassEnabled,
                              (void **)&orig_METAIsLiquidGlassEnabled);

    // Símbolos vistos no FBSharedFramework/IGLiquidGlass. São retornos BOOL;
    // a replacement ignora self/args e só devolve YES em w0.
    FBTHookDirectBoolIfExists("$s29IGLiquidGlassExperimentHelper0ab10NavigationcD0C9isEnabledSbyF",
                              (void *)fbt_AlwaysYES,
                              (void **)&orig_IGLiquidGlassNavigationExperiment_isEnabled);
    FBTHookDirectBoolIfExists("$s29IGLiquidGlassExperimentHelper017IGThrowbackChromecD0C9isEnabledSbyF",
                              (void *)fbt_AlwaysYES,
                              (void **)&orig_IGThrowbackChromeExperiment_isEnabled);

    FBTInstallLiquidGlassRuntimeBoolHooks();
    FBTLog(@"LiquidGlass hooks instalados");
}
