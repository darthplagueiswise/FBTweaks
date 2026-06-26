#import "FBTSettingsViewController.h"
#import "../FBTDefaults.h"
#import "../FBTUtils.h"
#import "../Runtime/FBTMobileConfigRuntime.h"
#import "../Runtime/FBTRuntimeBoolBrowser.h"
#import "FBTSymbolsBrowserViewController.h"
#import "FBTFeatureParamsViewController.h"
#import "../Runtime/FBTFlagCatalog.h"
#import "../Runtime/FBTNativeMobileConfigOverrides.h"
#import "../Features/Employee/FBTInternalImports.h"
#include <stdlib.h>

extern void FBTInstallLiquidGlassHooks(void);

static NSString * const FBTCellID = @"FBTCell";
static NSString * const FBTSwitchCellID = @"FBTSwitchCell";

static uint64_t FBTParseUInt64String(NSString *string) {
    if (![string isKindOfClass:[NSString class]] || !string.length) return 0;
    const char *cstr = [string UTF8String];
    if (!cstr) return 0;
    char *end = NULL;
    return (uint64_t)strtoull(cstr, &end, 0);
}

static long long FBTParseLongLongString(NSString *string) {
    if (![string isKindOfClass:[NSString class]] || !string.length) return 0;
    const char *cstr = [string UTF8String];
    if (!cstr) return 0;
    char *end = NULL;
    return strtoll(cstr, &end, 0);
}

static void FBTConfigureDefaultLiquidGlass(UIViewController *vc) {
    if (!vc.navigationController) return;
    UINavigationBarAppearance *nav = [UINavigationBarAppearance new];
    [nav configureWithDefaultBackground];
    vc.navigationController.navigationBar.standardAppearance = nav;
    vc.navigationController.navigationBar.scrollEdgeAppearance = nav;
    vc.navigationController.navigationBar.compactAppearance = nav;
    vc.navigationController.navigationBar.prefersLargeTitles = NO;
}

static UILabel *FBTSecondaryLabel(NSString *text) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = [UIColor secondaryLabelColor];
    label.numberOfLines = 0;
    return label;
}

static NSString *FBTBoolText(BOOL v) { return v ? @"ON" : @"OFF"; }

static BOOL FBTSettingsQueryMatchesHaystack(NSString *query, NSString *haystack) {
    NSString *q = [query.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (!q.length) return YES;
    NSString *h = haystack.lowercaseString ?: @"";
    NSArray<NSString *> *tokens = [q componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *token in tokens) {
        if (!token.length) continue;
        if ([h rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

@interface FBTSettingsSwitch : UISwitch
@property (nonatomic, copy) NSString *prefKey;
@end
@implementation FBTSettingsSwitch @end

@interface FBTSettingsViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@end

@interface FBTMobileConfigViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *searchController;
@end

@interface FBTRuntimeBoolViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *searchController;
@end

@interface FBTFlagDumpViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *flags;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL headlineOnly;
@end

@interface FBTQueryConfigViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation FBTSettingsBridge
+ (UIViewController *)makeSettingsController {
    FBTSettingsViewController *root = [[FBTSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithDefaultBackground];
    nav.navigationBar.standardAppearance = appearance;
    nav.navigationBar.scrollEdgeAppearance = appearance;
    nav.navigationBar.compactAppearance = appearance;
    return nav;
}
@end

@implementation FBTSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FBTweak";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeTapped)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:FBTCellID];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:FBTSwitchCellID];
    [self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    FBTConfigureDefaultLiquidGlass(self);
    [self.tableView reloadData];
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)rebuildSections {
    self.sections = @[
        @[
            @{ @"kind": @"switch", @"title": @"Tweak ativada", @"subtitle": @"Kill switch global.", @"key": FBTKeyMasterEnabled },
            @{ @"kind": @"switch", @"title": @"Long-press abre ajustes", @"subtitle": @"Segura a tab bar por ~0,6s.", @"key": FBTKeyOpenLongPress },
        ],
        @[
            @{ @"kind": @"switch", @"title": @"Employee / Internal", @"subtitle": @"Getters conhecidos via Logos/MSHookMessageEx.", @"key": FBTKeyEmployeeEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Employee sweep runtime", @"subtitle": @"Instala em runtime selectors BOOL reais contendo employee/test/internalTestUser.", @"key": FBTKeyEmployeeSweepEnabled },
            @{ @"kind": @"switch", @"title": @"Dogfood sweep runtime", @"subtitle": @"Instala em runtime selectors BOOL reais contendo dogfood/dogfooding/dogfooder.", @"key": FBTKeyDogfoodSweepEnabled },
            @{ @"kind": @"switch", @"title": @"Internal/debug sweep runtime", @"subtitle": @"Instala em runtime selectors BOOL reais de internal settings/debug menu/developer.", @"key": FBTKeyInternalDebugSweepEnabled },
            @{ @"kind": @"switch", @"title": @"C import: Internal Settings", @"subtitle": @"fishhook em FBShouldEnableInternalSettings importado pelo executable; toggle runtime após instalar.", @"key": FBTKeyInternalCImportsEnabled },
            @{ @"kind": @"switch", @"title": @"C import: EasyGating internal", @"subtitle": @"fishhook de teste em EasyGatingGetBoolean_Internal_DoNotUseOrMock; pode ser amplo, use isolado.", @"key": FBTKeyEasyGatingInternalEnabled },
            @{ @"kind": @"switch", @"title": @"Liquid Glass", @"subtitle": @"fishhook import + Runtime BOOL; sem patch direto em __TEXT assinado.", @"key": FBTKeyLiquidGlassEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Floating Tab Bar", @"subtitle": @"Getters conhecidos do tab bar.", @"key": FBTKeyFloatingTabBarEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Dating / Gemstone", @"subtitle": @"Gates Msys exportados; exige restart.", @"key": FBTKeyDatingEnabled, @"restart": @YES },
            @{ @"kind": @"nav", @"title": @"Liquid Glass — params", @"subtitle": @"Toggle por param MobileConfig (SYS/OFF/ON) via mc_overrides.json nativo.", @"dest": @"feat:LiquidGlass" },
            @{ @"kind": @"nav", @"title": @"Floating Tab Bar — params", @"subtitle": @"Toggle por param MobileConfig (SYS/OFF/ON) via mc_overrides.json nativo.", @"dest": @"feat:FloatingTab" },
            @{ @"kind": @"nav", @"title": @"Dating / Gemstone — gates", @"subtitle": @"Gates employee/test-user/internal via mc_overrides.json nativo.", @"dest": @"feat:DatingGemstone" },
        ],
        @[
            @{ @"kind": @"switch", @"title": @"MobileConfig runtime", @"subtitle": @"fishhook nos imports + captura ObjC/RCT MobileConfig pós-launch. Abrir MobileConfig Live também instala manualmente na sessão.", @"key": FBTKeyMobileConfigRuntimeEnabled },
            @{ @"kind": @"switch", @"title": @"Capturar leituras MobileConfig", @"subtitle": @"Guarda chave viva, tipo, default, resultado e contador.", @"key": FBTKeyMobileConfigCaptureEnabled },
            @{ @"kind": @"switch", @"title": @"Aplicar overrides MobileConfig", @"subtitle": @"Tenta OverridesTable nativo quando há contexto vivo; mantém fallback por accessor fishhookado.", @"key": FBTKeyMobileConfigOverridesEnabled },
            @{ @"kind": @"switch", @"title": @"Runtime BOOL browser", @"subtitle": @"Busca main-exec/FBShared/RN/framework por classe, selector e imagem; salva Force ON/OFF.", @"key": FBTKeyRuntimeBoolBrowserEnabled },
        ],
        @[
            @{ @"kind": @"nav", @"title": @"MobileConfig Live", @"subtitle": @"Monitor + override por uint64 capturado.", @"dest": @"mobileconfig" },
            @{ @"kind": @"nav", @"title": @"Runtime Browser", @"subtitle": @"Exec + FBShared + FBSharedDynamic + RN. Abas ObjC/C/DATA/Swift. Force ON/OFF.", @"dest": @"bool" },
            @{ @"kind": @"nav", @"title": @"Headline flags", @"subtitle": @"Flags filtradas: internal, dogfood, dating, debug.", @"dest": @"headline" },
            @{ @"kind": @"nav", @"title": @"Dump completo de flags", @"subtitle": @"FBTFlags.json empacotado.", @"dest": @"flags" },
            @{ @"kind": @"nav", @"title": @"Query configs enviados", @"subtitle": @"GraphQL IDs/variáveis empacotados no bundle.", @"dest": @"queries" },
        ],
        @[
            @{ @"kind": @"action", @"title": @"Abrir Internal Settings nativo", @"subtitle": @"Chama FBInternalSettingsViewControllerFromSession(session).", @"action": @"native" },
            @{ @"kind": @"action", @"title": @"Criar mc_overrides.json nativo", @"subtitle": @"Usa o path nativo capturado por getOverridesTablePath; abre o menu nativo antes se aparecer unknown.", @"action": @"ensure_mc_file" },
            @{ @"kind": @"action", @"title": @"Limpar overrides runtime", @"subtitle": @"Remove MobileConfig + ObjC BOOL overrides persistidos.", @"action": @"clear" },
        ],
    ];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Geral";
        case 1: return @"Hooks conhecidos";
        case 2: return @"Runtime";
        case 3: return @"Browsers";
        case 4: return @"Ações";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) return @"MobileConfig runtime instala fishhook nos imports e hooks ObjC/RCT leves pós-launch. O novo build importa FBMobileConfigSetSkipOverrideCheckEnabled; quando presente a tweak chama essa API antes de aplicar override nativo.";
    if (section == 3) return @"O browser ObjC não varre classes no launch. Agora a busca não descarta classes só pelo nome: selector útil como isEmployee/isDebugOptionsEnabled aparece mesmo em classes RN/Swift/Produto.";
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.sections[section].count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.sections[indexPath.section][indexPath.row];
    NSString *kind = item[@"kind"];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[kind isEqualToString:@"switch"] ? FBTSwitchCellID : FBTCellID forIndexPath:indexPath];
    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.numberOfLines = 0;

    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    cfg.text = item[@"title"];
    cfg.secondaryText = item[@"subtitle"];
    cfg.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    cfg.secondaryTextProperties.numberOfLines = 0;
    cell.contentConfiguration = cfg;

    if ([kind isEqualToString:@"switch"]) {
        FBTSettingsSwitch *sw = [FBTSettingsSwitch new];
        sw.prefKey = item[@"key"];
        sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:sw.prefKey];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([kind isEqualToString:@"nav"]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)showInfoTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)switchChanged:(FBTSettingsSwitch *)sender {
    [FBTDefaults setBool:sender.isOn forKey:sender.prefKey];
    if ([sender.prefKey isEqualToString:FBTKeyMobileConfigRuntimeEnabled]) {
        if (sender.isOn) {
            FBTInstallMobileConfigRuntime();
            FBTInstallNativeMobileConfigContextCapture();
        }
        FBTMobileConfigReloadPrefs();
    }
    if ([sender.prefKey isEqualToString:FBTKeyMobileConfigCaptureEnabled] ||
        [sender.prefKey isEqualToString:FBTKeyMobileConfigOverridesEnabled]) {
        FBTMobileConfigReloadPrefs();
    }
    if ([sender.prefKey isEqualToString:FBTKeyRuntimeBoolBrowserEnabled]) {
        FBTRuntimeBoolReloadPrefs();
        if (sender.isOn) FBTRuntimeBoolReinstallPersistedHooks();
    }
    if ([sender.prefKey isEqualToString:FBTKeyEmployeeSweepEnabled] && sender.isOn) {
        NSUInteger n = FBTRuntimeBoolInstallSweep(@"employee", YES, 160);
        [self showInfoTitle:@"Employee sweep" message:[NSString stringWithFormat:@"Instalados %lu hooks BOOL persistidos.", (unsigned long)n]];
    }
    if ([sender.prefKey isEqualToString:FBTKeyDogfoodSweepEnabled] && sender.isOn) {
        NSUInteger n = FBTRuntimeBoolInstallSweep(@"dogfood", YES, 160);
        [self showInfoTitle:@"Dogfood sweep" message:[NSString stringWithFormat:@"Instalados %lu hooks BOOL persistidos.", (unsigned long)n]];
    }
    if ([sender.prefKey isEqualToString:FBTKeyInternalDebugSweepEnabled] && sender.isOn) {
        NSUInteger n = FBTRuntimeBoolInstallSweep(@"internaldebug", YES, 160);
        [self showInfoTitle:@"Internal/debug sweep" message:[NSString stringWithFormat:@"Instalados %lu hooks BOOL persistidos.", (unsigned long)n]];
    }
    if ([sender.prefKey isEqualToString:FBTKeyInternalCImportsEnabled] ||
        [sender.prefKey isEqualToString:FBTKeyEasyGatingInternalEnabled]) {
        FBTInstallInternalImportHooks();
        FBTInternalImportReloadPrefs();
    }
    if ([sender.prefKey isEqualToString:FBTKeyLiquidGlassEnabled] && sender.isOn) {
        FBTInstallLiquidGlassHooks();
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.sections[indexPath.section][indexPath.row];
    NSString *kind = item[@"kind"];
    if ([kind isEqualToString:@"nav"]) {
        NSString *dest = item[@"dest"];
        UIViewController *vc = nil;
        if ([dest isEqualToString:@"mobileconfig"]) vc = [[FBTMobileConfigViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"bool"]) vc = [[FBTSymbolsBrowserViewController alloc] initWithMode:FBTCSymbolsBrowserModeObjCMethods];
        else if ([dest hasPrefix:@"feat:"]) vc = [[FBTFeatureParamsViewController alloc] initWithFeatureId:[dest substringFromIndex:5]];
        else if ([dest isEqualToString:@"headline"]) { FBTFlagDumpViewController *f = [[FBTFlagDumpViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; f.headlineOnly = YES; vc = f; }
        else if ([dest isEqualToString:@"flags"]) { FBTFlagDumpViewController *f = [[FBTFlagDumpViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; f.headlineOnly = NO; vc = f; }
        else if ([dest isEqualToString:@"queries"]) vc = [[FBTQueryConfigViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        if (vc) [self.navigationController pushViewController:vc animated:YES];
    } else if ([kind isEqualToString:@"action"]) {
        NSString *action = item[@"action"];
        if ([action isEqualToString:@"native"]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"FBTRequestOpenNativeInternalSettings" object:nil];
        } else if ([action isEqualToString:@"ensure_mc_file"]) {
            BOOL ok = FBTNativeMobileConfigEnsureOverridesFile();
            NSString *path = FBTNativeMobileConfigOverridesFilePath() ?: @"path ainda não capturado";
            UIAlertController *a = [UIAlertController alertControllerWithTitle:ok ? @"Arquivo pronto" : @"Sem path nativo" message:[NSString stringWithFormat:@"%@\n%@", path, FBTNativeMobileConfigStatus() ?: @""] preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        } else if ([action isEqualToString:@"clear"]) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Limpar overrides?" message:@"Remove overrides MobileConfig e Runtime BOOL salvos. Hooks já instalados continuam chamando orig quando não houver override." preferredStyle:UIAlertControllerStyleActionSheet];
            [a addAction:[UIAlertAction actionWithTitle:@"Limpar" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
                FBTMobileConfigClearAllOverrides();
                FBTRuntimeBoolClearAllOverrides();
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            a.popoverPresentationController.sourceView = cell;
            a.popoverPresentationController.sourceRect = cell.bounds;
            [self presentViewController:a animated:YES completion:nil];
        }
    }
}
@end

@implementation FBTMobileConfigViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig Live";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:FBTCellID];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadSnapshot)];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Buscar key, config ou param";
    self.navigationItem.searchController = self.searchController;
    // Ação manual pós-launch: evita o watchdog do ctor, mas faz o browser
    // funcionar quando o usuário abre a tela. Inclui RCTMobileConfigNative e
    // readers ObjC genéricos do novo FBReactNativeProductsFramework.
    FBTInstallMobileConfigRuntime();
    FBTInstallNativeMobileConfigContextCapture();
    FBTMobileConfigReloadPrefs();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadSnapshot) name:FBTMobileConfigDidUpdateNotification object:nil];
    [self reloadSnapshot];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; FBTConfigureDefaultLiquidGlass(self); [self reloadSnapshot]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)reloadSnapshot {
    self.navigationItem.prompt = FBTNativeMobileConfigStatus();
    self.entries = FBTMobileConfigSnapshot();
    [self applyFilter];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }

- (void)applyFilter {
    NSString *q = self.searchController.searchBar.text.lowercaseString ?: @"";
    if (!q.length) self.filtered = self.entries ?: @[];
    else {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, __unused NSDictionary *bindings) {
            NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@", e[@"key"] ?: @"", e[@"hex"] ?: @"", e[@"config"] ?: @"", e[@"param"] ?: @"", e[@"type"] ?: @""] lowercaseString];
            return FBTSettingsQueryMatchesHaystack(q, hay);
        }];
        self.filtered = [self.entries filteredArrayUsingPredicate:p];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX((NSInteger)self.filtered.count, 1); }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:FBTCellID forIndexPath:indexPath];
    if (!self.filtered.count) {
        UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
        cfg.text = @"Nenhuma leitura capturada ainda";
        cfg.secondaryText = [NSString stringWithFormat:@"Deixa MobileConfig runtime + captura ligados, reabre o Facebook se necessário, e navega nas telas que tu quer investigar. %@", FBTNativeMobileConfigStatus() ?: @""];
        cfg.secondaryTextProperties.numberOfLines = 0;
        cell.contentConfiguration = cfg;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *name = [e[@"param"] length] ? e[@"param"] : e[@"hex"];
    NSString *config = [e[@"config"] length] ? e[@"config"] : e[@"key"];
    NSString *forced = [e[@"forced"] boolValue] ? [NSString stringWithFormat:@"  FORCE %@=%@", e[@"forcedType"] ?: @"", e[@"forcedValue"] ?: @""] : @"";
    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    cfg.text = name;
    cfg.secondaryText = [NSString stringWithFormat:@"%@ · %@ · count %@ · result %@%@\n%@", config, e[@"type"] ?: @"?", e[@"count"] ?: @0, e[@"result"] ?: @"", forced, e[@"nativeStatus"] ?: FBTNativeMobileConfigStatus() ?: @""];
    cfg.secondaryTextProperties.numberOfLines = 3;
    cfg.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    cell.contentConfiguration = cfg;
    cell.accessoryType = [e[@"forced"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.filtered.count) return;
    NSDictionary *entry = self.filtered[indexPath.row];
    uint64_t key = FBTParseUInt64String(entry[@"key"]);
    NSString *type = entry[@"type"] ?: @"bool";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:entry[@"param"] ?: entry[@"hex"] message:[NSString stringWithFormat:@"%@\nkey %@\n%@", entry[@"config"] ?: @"", entry[@"hex"] ?: @"", FBTNativeMobileConfigStatus() ?: @""] preferredStyle:UIAlertControllerStyleActionSheet];
    if ([type isEqualToString:@"bool"]) {
        [a addAction:[UIAlertAction actionWithTitle:@"Force TRUE" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { FBTMobileConfigSetOverride(key, @"bool", @YES); [self reloadSnapshot]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Force FALSE" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { FBTMobileConfigSetOverride(key, @"bool", @NO); [self reloadSnapshot]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Force int64…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { [self promptValueForKey:key type:@"int64" title:@"Force int64"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force double…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { [self promptValueForKey:key type:@"double" title:@"Force double"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force string…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { [self promptValueForKey:key type:@"string" title:@"Force string"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Limpar override" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) { FBTMobileConfigClearOverride(key); [self reloadSnapshot]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    a.popoverPresentationController.sourceView = cell;
    a.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptValueForKey:(uint64_t)key type:(NSString *)type title:(NSString *)title {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = type; tf.keyboardType = [type isEqualToString:@"string"] ? UIKeyboardTypeDefault : UIKeyboardTypeNumbersAndPunctuation; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Aplicar" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
        NSString *s = a.textFields.firstObject.text ?: @"";
        id value = s;
        if ([type isEqualToString:@"int64"]) value = @(FBTParseLongLongString(s));
        else if ([type isEqualToString:@"double"]) value = @([s doubleValue]);
        FBTMobileConfigSetOverride(key, type, value);
        [self reloadSnapshot];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

@implementation FBTRuntimeBoolViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ObjC BOOL Runtime";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:FBTCellID];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Buscar" style:UIBarButtonItemStylePlain target:self action:@selector(runSearch)];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Classe/selector/image: dogfood, FBShared, main-exec…";
    self.navigationItem.searchController = self.searchController;
    [self runSearch];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; FBTConfigureDefaultLiquidGlass(self); }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text.lowercaseString ?: @"";
    if (!q.length) self.filtered = self.entries ?: @[];
    else self.filtered = [self.entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, __unused NSDictionary *b) {
        NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@ %@", e[@"class"] ?: @"", e[@"selector"] ?: @"", e[@"imageKind"] ?: @"", e[@"image"] ?: @""] lowercaseString];
        return FBTSettingsQueryMatchesHaystack(q, hay);
    }]];
    [self.tableView reloadData];
}

- (void)runSearch {
    NSString *q = self.searchController.searchBar.text ?: @"";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *result = FBTRuntimeBoolSearch(q, 400);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.entries = result;
            self.filtered = result;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX((NSInteger)self.filtered.count, 1); }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:FBTCellID forIndexPath:indexPath];
    if (!self.filtered.count) {
        UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
        cfg.text = @"Nenhum getter BOOL encontrado";
        cfg.secondaryText = @"Busca por termos como dogfood, internal, employee, debug, RCT, React, FBShared ou main-exec. A busca aceita múltiplas palavras e roda só pós-launch.";
        cfg.secondaryTextProperties.numberOfLines = 0;
        cell.contentConfiguration = cfg;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *e = self.filtered[indexPath.row];
    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    cfg.text = [NSString stringWithFormat:@"%@%@", [e[@"classMethod"] boolValue] ? @"+" : @"-", e[@"selector"] ?: @""];
    NSString *force = [e[@"forced"] boolValue] ? [NSString stringWithFormat:@" · FORCE %@", FBTBoolText([e[@"force"] boolValue])] : @"";
    cfg.secondaryText = [NSString stringWithFormat:@"%@ · %@%@", e[@"class"] ?: @"", e[@"imageKind"] ?: @"unknown", force];
    cfg.secondaryTextProperties.numberOfLines = 3;
    cfg.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    cell.contentConfiguration = cfg;
    cell.accessoryType = [e[@"forced"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.filtered.count) return;
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *msg = [NSString stringWithFormat:@"%@\n%@", e[@"class"] ?: @"", e[@"image"] ?: @""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:e[@"selector"] message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { FBTRuntimeBoolSetOverride(e, YES); [self runSearch]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { FBTRuntimeBoolSetOverride(e, NO); [self runSearch]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Desfazer override" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) { FBTRuntimeBoolClearOverride(e); [self runSearch]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    a.popoverPresentationController.sourceView = cell;
    a.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:a animated:YES completion:nil];
}
@end

@implementation FBTFlagDumpViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.headlineOnly ? @"Headline flags" : @"Flags";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:FBTCellID];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Buscar config ou param";
    self.navigationItem.searchController = self.searchController;
    self.flags = self.headlineOnly ? [FBTFlagCatalog headlineFlags] : [FBTFlagCatalog allFlags];
    [self applyFilter];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; FBTConfigureDefaultLiquidGlass(self); }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }
- (void)applyFilter {
    NSString *q = self.searchController.searchBar.text.lowercaseString ?: @"";
    if (!q.length) self.filtered = self.flags ?: @[];
    else self.filtered = [self.flags filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *f, __unused NSDictionary *b) {
        NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", f[@"c"] ?: @"", f[@"p"] ?: @"", f[@"tag"] ?: @""] lowercaseString];
        return FBTSettingsQueryMatchesHaystack(q, hay);
    }]];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:FBTCellID forIndexPath:indexPath];
    NSDictionary *f = self.filtered[indexPath.row];
    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    cfg.text = f[@"p"] ?: @"";
    cfg.secondaryText = [NSString stringWithFormat:@"%@ · %@ · default %@ · sid %@", f[@"c"] ?: @"", f[@"t"] ?: @"?", f[@"d"] ?: @"—", f[@"sid"] ?: @0];
    cfg.secondaryTextProperties.numberOfLines = 3;
    cfg.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    cell.contentConfiguration = cfg;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}
@end

@implementation FBTQueryConfigViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Query configs";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:FBTCellID];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Buscar query, id ou arquivo";
    self.navigationItem.searchController = self.searchController;
    self.items = [FBTFlagCatalog queryConfigs];
    [self applyFilter];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; FBTConfigureDefaultLiquidGlass(self); }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }
- (void)applyFilter {
    NSString *q = self.searchController.searchBar.text.lowercaseString ?: @"";
    if (!q.length) self.filtered = self.items ?: @[];
    else self.filtered = [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, __unused NSDictionary *b) {
        NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", item[@"name"] ?: @"", item[@"id"] ?: @"", item[@"file"] ?: @""] lowercaseString];
        return FBTSettingsQueryMatchesHaystack(q, hay);
    }]];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX((NSInteger)self.filtered.count, 1); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:FBTCellID forIndexPath:indexPath];
    if (!self.filtered.count) {
        UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
        cfg.text = @"Nenhum QueryConfig empacotado";
        cfg.secondaryText = @"Os JSONs enviados devem estar em FBTweak.bundle/QueryConfigs/.";
        cfg.secondaryTextProperties.numberOfLines = 0;
        cell.contentConfiguration = cfg;
        return cell;
    }
    NSDictionary *item = self.filtered[indexPath.row];
    NSArray *vars = [item[@"variables"] isKindOfClass:[NSArray class]] ? item[@"variables"] : @[];
    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    cfg.text = item[@"name"] ?: @"";
    NSString *varsText = vars.count ? [vars componentsJoinedByString:@", "] : (item[@"value"] ?: @"—");
    cfg.secondaryText = [NSString stringWithFormat:@"id %@ · %@\nvars/value: %@", item[@"id"] ?: @"—", item[@"file"] ?: @"", varsText];
    cfg.secondaryTextProperties.numberOfLines = 4;
    cfg.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    cell.contentConfiguration = cfg;
    return cell;
}
@end
