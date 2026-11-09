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

// Navigate the actual plugin row of the Facebook Internal Settings provider.
// This is NOT a textual search or a synthetic controller: a real table row
// is selected through the original UITableViewDelegate callback.
static NSString *FBTNativePluginCellTitle(UITableViewCell *cell) {
    if (!cell) return @"";
    id configuration = cell.contentConfiguration;
    NSString *text = nil;
    if ([configuration isKindOfClass:[UIListContentConfiguration class]])
        text = ((UIListContentConfiguration *)configuration).text;
    if (!text.length) text = cell.textLabel.text;
    if (!text.length) text = cell.accessibilityLabel;
    return text ?: @"";
}

static BOOL FBTSelectNativeInternalPlugin(UIViewController *root, NSString *plugin,
                                          NSString **failure) {
    if (!plugin.length) return YES;
    UITableViewController *tableController =
        [root isKindOfClass:[UITableViewController class]] ? (id)root : nil;
    if (!tableController && [root isKindOfClass:[UINavigationController class]]) {
        UIViewController *top = [(UINavigationController *)root topViewController];
        if ([top isKindOfClass:[UITableViewController class]]) tableController = (id)top;
    }
    UITableView *table = tableController.tableView;
    if (!table || !table.dataSource || !table.delegate ||
        ![table.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        if (failure) *failure = @"A raiz de Internal Settings não expôs UITableView/DataSource/Delegate nativos.";
        return NO;
    }
    [table reloadData];
    NSInteger sections = MIN(40, [table numberOfSections]);
    NSUInteger visited = 0;
    NSString *needle = plugin.lowercaseString;
    NSIndexPath *found = nil;
    for (NSInteger section = 0; section < sections && !found && visited < 2000; section++) {
        NSInteger rows = MIN(250, [table numberOfRowsInSection:section]);
        for (NSInteger row = 0; row < rows && visited++ < 2000; row++) {
            NSIndexPath *idx = [NSIndexPath indexPathForRow:row inSection:section];
            UITableViewCell *cell = nil;
            @try { cell = [table.dataSource tableView:table cellForRowAtIndexPath:idx]; }
            @catch (__unused NSException *exception) { continue; }
            NSString *title = FBTNativePluginCellTitle(cell).lowercaseString;
            // Prefer exact plugin matches, do not select arbitrary substrings.
            BOOL match = [title isEqualToString:needle] ||
                [title hasPrefix:[needle stringByAppendingString:@" "]] ||
                [title hasPrefix:[needle stringByAppendingString:@" —"]] ||
                [title hasPrefix:[needle stringByAppendingString:@" /"]];
            if (match) { found = idx; break; }
        }
    }
    if (!found) {
        if (failure) *failure = [NSString stringWithFormat:
            @"O provider de Internal Settings não registrou uma row para %@ nesta sessão (%lu rows verificadas). Não houve busca nem menu falso.",
            plugin, (unsigned long)visited];
        return NO;
    }
    @try {
        [table.delegate tableView:table didSelectRowAtIndexPath:found];
        FBTLog(@"Native Internal Settings plugin selected: %@ at %@", plugin, found);
        return YES;
    } @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:
            @"O plugin %@ lançou exceção ao selecionar sua row original: %@",
            plugin, exception.reason ?: exception.name];
        return NO;
    }
}

static void fbt_openNativeInternalSettings(NSString *targetPlugin) {
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

        [presenter presentViewController:nav animated:YES completion:^{
            if (!targetPlugin.length) return;
            NSString *failure = nil;
            if (!FBTSelectNativeInternalPlugin(vc, targetPlugin, &failure)) {
                [FBTUtils showMessage:failure ?: @"Plugin nativo indisponível."
                               title:[NSString stringWithFormat:@"%@ — Internal", targetPlugin]];
            }
        }];
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
                usingBlock:^(NSNotification *note) {
                    NSString *target = [note.userInfo[@"nativePlugin"] isKindOfClass:[NSString class]]
                        ? note.userInfo[@"nativePlugin"] : nil;
                    fbt_openNativeInternalSettings(target);
                }];
    });
}
