#import "FBTPrefix.h"
#import "FBTUtils.h"
#import "FBTDefaults.h"
#import "Runtime/FBTMobileConfigDebugUIHooks.h"
#import <dlfcn.h>

// Categoria utilitária p/ o seletor de fechar do painel nativo.
@interface UINavigationController (FBTInternalSettings)
- (void)fbt_dismissInternalSettings;
@end

// =====================================================================
// Dogfood — abre a tela NATIVA de Internal Settings do Facebook.
//
// Função C confirmada (exportada por FBSharedFramework, __text):
//   _FBInternalSettingsViewControllerFromSession  @ 0x52443b8 (Facebook 583)
//   assinatura: UIViewController *(*)(id session)
// Constrói a VC Bloks de internal settings do próprio app.
//
// O painel UIKit (desacoplado) dispara uma NSNotification; este
// observer resolve a função por dlsym e apresenta a VC usando a sessão
// guardada pelo Tweak.x. Nada disso é hook — é chamada direta sob ação
// do usuário. Por isso não há grupo Logos aqui.
// =====================================================================

NSString * const FBTNotifOpenNativeInternalSettings = @"FBTRequestOpenNativeInternalSettings";

void FBTOpenNativeWhitehatSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"FBWhitehatSettingsViewController");
        if (!cls) {
            NSString *path = [[NSBundle mainBundle].privateFrameworksPath
                stringByAppendingPathComponent:@"FBRarelyUsedFramework.framework"];
            if (path.length) [[NSBundle bundleWithPath:path] loadAndReturnError:nil];
            cls = NSClassFromString(@"FBWhitehatSettingsViewController");
        }
        if (!cls || ![cls isSubclassOfClass:[UIViewController class]]) {
            [FBTUtils showMessage:@"A tela Whitehat não está disponível neste aplicativo." title:@"Whitehat"];
            return;
        }
        // The native menu handler uses +new, without session arguments.
        UIViewController *vc = [cls new];
        UIViewController *presenter = [FBTUtils topMostController];
        if (!presenter || presenter.isBeingDismissed) return;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:nav
            action:@selector(fbt_dismissInternalSettings)];
        [presenter presentViewController:nav animated:YES completion:nil];
    });
}

typedef UIViewController *(*FBTInternalSettingsFn)(id session);
extern void FBTInstallKnownGateRuntimeHooks(void);

static void fbt_openNativeInternalSettings(void) {
    // Register the late native-UI bootstrap before creating the Internal
    // Settings surface. Context/readers are warmed when the actual
    // FBMobileConfigDebugViewController enters, avoiding the old one-shot scan
    // before FBRarelyUsedFramework was loaded. Server QE failures remain native.
    FBTInstallMobileConfigDebugUIBootstrap();
    FBTInstallKnownGateRuntimeHooks();

    id session = [FBTUtils storedSession];
    if (!session) {
        FBTLog(@"internal settings: sem sessão guardada");
        [FBTUtils showMessage:@"Abra uma conta no Facebook e tente novamente." title:@"Internal Settings"];
        return;
    }

    FBTInternalSettingsFn fn =
        (FBTInternalSettingsFn)dlsym(RTLD_DEFAULT, "FBInternalSettingsViewControllerFromSession");
    if (!fn) {
        FBTLog(@"internal settings: símbolo não resolvido");
        [FBTUtils showMessage:@"O aplicativo não disponibilizou o construtor nativo de Internal Settings." title:@"Internal Settings"];
        return;
    }

    UIViewController *vc = nil;
    @try {
        vc = fn(session);
    } @catch (NSException *e) {
        FBTLog(@"internal settings: exceção %@", e);
        [FBTUtils showMessage:@"A tela nativa não pôde ser criada. Consulte o diagnóstico." title:@"Internal Settings"];
        return;
    }
    if (![vc isKindOfClass:[UIViewController class]]) {
        [FBTUtils showMessage:@"A sessão atual não retornou uma tela nativa de Internal Settings." title:@"Internal Settings"];
        return;
    }

    // The function above may load additional internal bundles synchronously.
    FBTInstallMobileConfigDebugUIHooks();

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
    static dispatch_once_t once;
    dispatch_once(&once, ^{
    [[NSNotificationCenter defaultCenter]
        addObserverForName:FBTNotifOpenNativeInternalSettings
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(__unused NSNotification *note) {
                    fbt_openNativeInternalSettings();
                }];
    });
}
