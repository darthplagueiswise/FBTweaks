#import "FBTPrefix.h"
#import "FBTDefaults.h"
#include "../../../modules/fishhook/fishhook.h"

// Hooks seguros: somente símbolos C IMPORTADOS pelo Facebook (GOT). Não patcha __TEXT.
// ABI validada por disasm do FBSharedFramework (chained-fixup aware via LIEF):
//   FBShouldEnableInternalSettings              -> recebe 1 arg (x0 = session)   [0xc32938: mov x19,x0]
//   EasyGatingGetBoolean_Internal_DoNotUseOrMock-> recebe 4 args (x0..x3)        [0x99245c: usa x0,x1,x2,x3]
// MCQEasyGatingGetBooleanInternalDoNotUseOrMock NÃO é importado pelo Facebook -> removido (era no-op).
// Decisão usa flags estáticas (sem NSUserDefaults em hot path); recarregadas via NotificationCenter.

typedef BOOL (*FBTShouldEnableFn)(void *session);
typedef BOOL (*FBTEasyGatingFn)(void *a0, void *a1, void *a2, void *a3);

static BOOL sInternalImportsEnabled = NO;
static BOOL sEasyGatingInternalEnabled = NO;
static BOOL sInstalled = NO;

static FBTShouldEnableFn orig_FBShouldEnableInternalSettings = NULL;
static FBTEasyGatingFn   orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock = NULL;

static BOOL fbt_FBShouldEnableInternalSettings(void *session) {
    if (sInternalImportsEnabled) return YES;
    return orig_FBShouldEnableInternalSettings ? orig_FBShouldEnableInternalSettings(session) : NO;
}

static BOOL fbt_EasyGatingGetBoolean_Internal_DoNotUseOrMock(void *a0, void *a1, void *a2, void *a3) {
    if (sEasyGatingInternalEnabled) return YES;
    return orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock
        ? orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock(a0, a1, a2, a3)
        : NO;
}

void FBTInternalImportReloadPrefs(void) {
    sInternalImportsEnabled    = [FBTDefaults boolForKey:FBTKeyInternalCImportsEnabled];
    sEasyGatingInternalEnabled = [FBTDefaults boolForKey:FBTKeyEasyGatingInternalEnabled];
}

void FBTInstallInternalImportHooks(void) {
    FBTInternalImportReloadPrefs();
    if (sInstalled) return;
    sInstalled = YES;

    struct rebinding rbs[] = {
        { "FBShouldEnableInternalSettings",
          (void *)fbt_FBShouldEnableInternalSettings,
          (void **)&orig_FBShouldEnableInternalSettings },
        { "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
          (void *)fbt_EasyGatingGetBoolean_Internal_DoNotUseOrMock,
          (void **)&orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock },
    };
    rebind_symbols(rbs, 2);
    FBTLog(@"internal import hooks installed: internal=%d easy=%d", sInternalImportsEnabled, sEasyGatingInternalEnabled);
}

NSDictionary *FBTInternalImportStatus(void) {
    return @{
        @"installed": @(sInstalled),
        @"internalImportsEnabled": @(sInternalImportsEnabled),
        @"easyGatingInternalEnabled": @(sEasyGatingInternalEnabled),
        @"FBShouldEnableInternalSettings": @(orig_FBShouldEnableInternalSettings != NULL),
        @"EasyGatingGetBoolean_Internal_DoNotUseOrMock": @(orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock != NULL),
    };
}
