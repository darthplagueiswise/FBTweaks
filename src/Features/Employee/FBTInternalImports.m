#import "FBTPrefix.h"
#import "FBTDefaults.h"
#include "../../../modules/fishhook/fishhook.h"

// Hooks seguros: somente símbolos C IMPORTADOS/GOT. Não patcha __TEXT.
// São toggles de teste: o hook fica instalado, mas a decisão usa flags estáticas
// atualizadas por NotificationCenter; desligar volta a chamar orig.

typedef BOOL (*FBTBoolVoidFn)(void);
typedef BOOL (*FBTBoolVarFn)(void);

static BOOL sInternalImportsEnabled = NO;
static BOOL sEasyGatingInternalEnabled = NO;
static BOOL sInstalled = NO;

static FBTBoolVoidFn orig_FBShouldEnableInternalSettings = NULL;
static FBTBoolVarFn orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock = NULL;
static FBTBoolVarFn orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock = NULL;

static BOOL fbt_FBShouldEnableInternalSettings(void) {
    if (sInternalImportsEnabled) return YES;
    return orig_FBShouldEnableInternalSettings ? orig_FBShouldEnableInternalSettings() : NO;
}

static BOOL fbt_EasyGatingGetBoolean_Internal_DoNotUseOrMock(void) {
    if (sEasyGatingInternalEnabled) return YES;
    return orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock ? orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock() : NO;
}

static BOOL fbt_MCQEasyGatingGetBooleanInternalDoNotUseOrMock(void) {
    if (sEasyGatingInternalEnabled) return YES;
    return orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock ? orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock() : NO;
}

void FBTInternalImportReloadPrefs(void) {
    sInternalImportsEnabled = [FBTDefaults boolForKey:FBTKeyInternalCImportsEnabled];
    sEasyGatingInternalEnabled = [FBTDefaults boolForKey:FBTKeyEasyGatingInternalEnabled];
}

void FBTInstallInternalImportHooks(void) {
    FBTInternalImportReloadPrefs();
    if (sInstalled) return;
    sInstalled = YES;

    struct rebinding rbs[] = {
        { "FBShouldEnableInternalSettings", (void *)fbt_FBShouldEnableInternalSettings, (void **)&orig_FBShouldEnableInternalSettings },
        { "EasyGatingGetBoolean_Internal_DoNotUseOrMock", (void *)fbt_EasyGatingGetBoolean_Internal_DoNotUseOrMock, (void **)&orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock },
        { "MCQEasyGatingGetBooleanInternalDoNotUseOrMock", (void *)fbt_MCQEasyGatingGetBooleanInternalDoNotUseOrMock, (void **)&orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock },
    };
    rebind_symbols(rbs, 3);
    FBTLog(@"internal import hooks installed: internal=%d easy=%d", sInternalImportsEnabled, sEasyGatingInternalEnabled);
}

NSDictionary *FBTInternalImportStatus(void) {
    return @{
        @"installed": @(sInstalled),
        @"internalImportsEnabled": @(sInternalImportsEnabled),
        @"easyGatingInternalEnabled": @(sEasyGatingInternalEnabled),
        @"FBShouldEnableInternalSettings": @(orig_FBShouldEnableInternalSettings != NULL),
        @"EasyGatingGetBoolean_Internal_DoNotUseOrMock": @(orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock != NULL),
        @"MCQEasyGatingGetBooleanInternalDoNotUseOrMock": @(orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock != NULL),
    };
}
