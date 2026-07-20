#import "FBTPrefix.h"
#import "FBTUtils.h"
#import "FBTDefaults.h"
#import "Runtime/FBTMobileConfigRuntime.h"
#import "Runtime/FBTNativeMobileConfigOverrides.h"
#import <dlfcn.h>

// Categoria utilitária p/ o seletor de fechar do painel nativo.
@interface UINavigationController (FBTInternalSettings)
- (void)fbt_dismissInternalSettings;
@end

// =====================================================================
// Dogfood — abre a tela NATIVA de Internal Settings do Facebook.
//
// Função C confirmada (exportada por FBSharedFramework, __text):
//   _FBInternalSettingsViewControllerFromSession  @ 0x2f70f90
//   assinatura: UIViewController *(*)(id session)
// Constrói a VC Bloks de internal settings do próprio app.
//
// O painel UIKit (desacoplado) dispara uma NSNotification; este
// observer resolve a função por dlsym e apresenta a VC usando a sessão
// guardada pelo Tweak.x. Nada disso é hook — é chamada direta sob ação
// do usuário. Por isso não há grupo Logos aqui.
// =====================================================================

NSString * const FBTNotifOpenNativeInternalSettings = @"FBTRequestOpenNativeInternalSettings";

typedef UIViewController *(*FBTInternalSettingsFn)(id session);
extern void FBTInstallKnownGateRuntimeHooks(void);

static void fbt_openNativeInternalSettings(void) {
    // Install the light post-launch capture before the native MobileConfig UI
    // is reached. This reduces the context-manager race seen when opening a
    // param immediately after entering Internal Settings. It does not fake a
    // failed server QE-info response.
    FBTInstallMobileConfigRuntime();
    FBTInstallNativeMobileConfigContextCapture();
    FBTMobileConfigReloadPrefs();
    FBTInstallKnownGateRuntimeHooks();

    id session = [FBTUtils storedSession];
    if (!session) {
        FBTLog(@"internal settings: sem sessão guardada");
        return;
    }

    FBTInternalSettingsFn fn =
        (FBTInternalSettingsFn)dlsym(RTLD_DEFAULT, "FBInternalSettingsViewControllerFromSession");
    if (!fn) {
        FBTLog(@"internal settings: símbolo não resolvido");
        return;
    }

    UIViewController *vc = nil;
    @try {
        vc = fn(session);
    } @catch (NSException *e) {
        FBTLog(@"internal settings: exceção %@", e);
        return;
    }
    if (![vc isKindOfClass:[UIViewController class]]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = [FBTUtils topMostController];
        if (!presenter) return;

        UINavigationController *nav =
            [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;

        // Botão de fechar (a VC nativa não traz um por conta própria).
        UIBarButtonItem *close =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                          target:nav
                                                          action:@selector(fbt_dismissInternalSettings)];
        if (!vc.navigationItem.leftBarButtonItem) {
            vc.navigationItem.leftBarButtonItem = close;
        } else {
            vc.navigationItem.rightBarButtonItem = close;
        }

        [presenter presentViewController:nav animated:YES completion:nil];
    });
}

@implementation UINavigationController (FBTInternalSettings)
- (void)fbt_dismissInternalSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

// Chamado uma vez pelo Tweak.x no ctor (barato; só registra observer).
void FBTInstallDogfoodObserver(void) {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:FBTNotifOpenNativeInternalSettings
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(__unused NSNotification *note) {
                    fbt_openNativeInternalSettings();
                }];
}
