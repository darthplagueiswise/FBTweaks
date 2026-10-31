#import "FBTSettingsViewController.h"
#import "FBTLocalConfigViewController.h"
#import "FBTNamesDiagnosticsViewController.h"
#import "FBTNetworkInspectorViewController.h"
#import "FBTNativeTraceViewController.h"
#import "FBTHookAuditViewController.h"
#import "../FBTDefaults.h"
#import "../FBTUtils.h"
#import "../Runtime/FBTMobileConfigRuntime.h"
#import "../Runtime/FBTRuntimeBoolBrowser.h"
#import "FBTSymbolsBrowserViewController.h"
#import "FBTFeatureParamsViewController.h"
#import "../Runtime/FBTFlagCatalog.h"
#import "../Runtime/FBTNativeMobileConfigOverrides.h"
#import "../Runtime/FBTMCOverridesFile.h"
#import "../Runtime/FBTMCPreferencesAudit.h"
#import "../Runtime/FBTMobileConfigFetchDiagnostics.h"
#import "../Runtime/FBTMobileConfigResponseCapture.h"
#import "../Runtime/FBTMCNativeSessionProbes.h"
#import "../Runtime/FBTMobileConfigDebugUIHooks.h"
#import "../Features/Employee/FBTInternalImports.h"
#include <stdlib.h>
#include <errno.h>
#include <math.h>

extern void FBTInstallLiquidGlassHooks(void);
extern void FBTOpenNativeWhitehatSettings(void);

static NSString * const FBTCellID = @"FBTCell";
static NSString * const FBTSwitchCellID = @"FBTSwitchCell";
static NSString * const FBTQESnapshotValidKey = @"FBTQESnapshotValid";
static NSString * const FBTQESnapshotLegacyStateKey = @"FBTQESnapshotLegacyState";
static NSString * const FBTQESnapshotBuiltinHashStateKey = @"FBTQESnapshotBuiltinHashState";
static NSString * const FBTQELegacyConfigKey = @"84491:mobile_config_internal_settings_features";
static NSString * const FBTQEBuiltinHashConfigKey = @"4626:mobileconfig_session";

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
    // Preserve the system-owned navigation bar material. A forced opaque
    // UINavigationBarAppearance defeats native Liquid Glass on iOS 26+.
    if (@available(iOS 26.0, *)) {
        vc.navigationController.navigationBar.prefersLargeTitles = YES;
        vc.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAutomatic;
    } else {
        vc.navigationController.navigationBar.prefersLargeTitles = NO;
    }
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

static NSString *FBTMCStateLabel(FBTMCState state) {
    switch (state) {
        case FBTMCStateOff: return @"OFF";
        case FBTMCStateOn: return @"ON";
        case FBTMCStateSys:
        default: return @"SYS (sem override explícito)";
    }
}

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
@property (nonatomic, assign) NSInteger entityMode;
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
    // Let UIKit render the native material, including Liquid Glass on iOS 26+.
    if (@available(iOS 26.0, *)) nav.navigationBar.prefersLargeTitles = YES;
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
    // A single source of truth for navigation. No shadowed probe toggles:
    // the Diagnostics Center owns capture, fetcher, Tigon and QE experiments.
    self.sections = @[
        @[
            @{ @"kind": @"switch", @"title": @"FBTweak ativa", @"subtitle": @"Chave geral dos hooks; desligar interrompe a aplicação de forças sem apagar preferências.", @"key": FBTKeyMasterEnabled },
            @{ @"kind": @"switch", @"title": @"Abrir com toque de três dedos", @"subtitle": @"Toque duplo com três dedos para abrir a central.", @"key": FBTKeyOpenThreeFingerDoubleTap },
            @{ @"kind": @"nav", @"title": @"Centro de Diagnósticos", @"subtitle": @"Captura, probes, experimento A/B, estado de execução e histórico em um só lugar.", @"dest": @"namesdiagnostic" },
        ],
        @[
            @{ @"kind": @"switch", @"title": @"Employee (estado local)", @"subtitle": @"Aplica somente getters conhecidos. Não comprova identidade nem autorização remota.", @"key": FBTKeyEmployeeEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Mobile Lab no lançamento", @"subtitle": @"LAB_IS_ACTIVE antes dos hooks. Reinicie o processo; não concede autorização no servidor.", @"key": FBTKeyMobileLabEnabled, @"restart": @YES },
            @{ @"kind": @"action", @"title": @"Abrir Internal Settings do Facebook", @"subtitle": @"Tenta a entrada nativa usando a sessão atual; requer os gates do próprio app.", @"action": @"native" },
            @{ @"kind": @"action", @"title": @"Abrir diagnóstico Whitehat nativo", @"subtitle": @"Acesso apenas à interface disponibilizada pelo aplicativo.", @"action": @"whitehat" },
        ],
        @[
            @{ @"kind": @"switch", @"title": @"Leitores MobileConfig", @"subtitle": @"Ativa sessão e leitores nativos; não altera automaticamente resultados de rede.", @"key": FBTKeyMobileConfigRuntimeEnabled },
            @{ @"kind": @"switch", @"title": @"Registrar leituras MobileConfig", @"subtitle": @"Histórico de getters, tipos e valores; pode afetar desempenho.", @"key": FBTKeyMobileConfigCaptureEnabled },
            @{ @"kind": @"switch", @"title": @"Aplicar overrides MobileConfig", @"subtitle": @"Tenta tabela nativa e fallback; confira o resultado efetivo no runtime.", @"key": FBTKeyMobileConfigOverridesEnabled },
            @{ @"kind": @"nav", @"title": @"Catálogo e overrides", @"subtitle": @"Pesquise configurações por ID ou nome; SYS, ON, OFF.", @"dest": @"localconfig" },
            @{ @"kind": @"nav", @"title": @"MobileConfig Live", @"subtitle": @"Leituras efetivas, origem, overrides e diagnóstico da sessão.", @"dest": @"mobileconfig" },
        ],
        @[
            @{ @"kind": @"switch", @"title": @"Liquid Glass no aplicativo", @"subtitle": @"Hooks de aparência do Facebook; requer cold start.", @"key": FBTKeyLiquidGlassEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Floating Tab Bar", @"subtitle": @"Hooks de tab bar; requer cold start.", @"key": FBTKeyFloatingTabBarEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Dating / Gemstone", @"subtitle": @"Gates locais; nenhum efeito remoto é presumido.", @"key": FBTKeyDatingEnabled, @"restart": @YES },
            @{ @"kind": @"nav", @"title": @"Parâmetros Liquid Glass", @"subtitle": @"Overrides nativos por configuração.", @"dest": @"feat:LiquidGlass" },
            @{ @"kind": @"nav", @"title": @"Parâmetros Floating Tab Bar", @"subtitle": @"Overrides nativos por configuração.", @"dest": @"feat:FloatingTab" },
            @{ @"kind": @"nav", @"title": @"Gates Dating / Gemstone", @"subtitle": @"Controles e pré-requisitos específicos.", @"dest": @"feat:DatingGemstone" },
        ],
        @[
            @{ @"kind": @"switch", @"title": @"Habilitar Runtime BOOL Browser", @"subtitle": @"Chave geral. Um override salvo só atua depois de um hook instalado e chamado.", @"key": FBTKeyRuntimeBoolBrowserEnabled },
            @{ @"kind": @"switch", @"title": @"Sweep Dogfood (avançado)", @"subtitle": @"Aplica somente selectors verificados; mostra número de instalações reais. Desligar limpa apenas esse sweep.", @"key": FBTKeyDogfoodSweepEnabled },
            @{ @"kind": @"switch", @"title": @"Sweep Internal/Debug (avançado)", @"subtitle": @"Mesmo fluxo de verificação e limpeza isolada. Pode afetar funções do app.", @"key": FBTKeyInternalDebugSweepEnabled },
            @{ @"kind": @"switch", @"title": @"Import FBShouldEnableInternalSettings", @"subtitle": @"Hook C específico; exige validação de import no executável.", @"key": FBTKeyInternalCImportsEnabled },
            @{ @"kind": @"switch", @"title": @"Import EasyGating (experimental)", @"subtitle": @"Interceptação C ampla: deixe desativada salvo diagnóstico controlado.", @"key": FBTKeyEasyGatingInternalEnabled },
            @{ @"kind": @"nav", @"title": @"Runtime Browser — métodos BOOL e ivars", @"subtitle": @"Enumeração por type encoding, classe, selector, assinatura, chamadas e estado.", @"dest": @"boollive" },
            @{ @"kind": @"nav", @"title": @"Auditoria de hooks", @"subtitle": @"Registrados, executados, pendentes e recusados com motivo real.", @"dest": @"hookaudit" },
            @{ @"kind": @"nav", @"title": @"Native Live Trace", @"subtitle": @"Registro estruturado de chamadas; preferir uso temporário.", @"dest": @"livetrace" },
            @{ @"kind": @"nav", @"title": @"Network Inspector", @"subtitle": @"Requests e responses correlacionados; exportação sanitizada.", @"dest": @"networkinspector" },
        ],
        @[
            @{ @"kind": @"nav", @"title": @"Flags relevantes", @"subtitle": @"Employee, internal, dogfood, debug e outros grupos.", @"dest": @"headline" },
            @{ @"kind": @"nav", @"title": @"Todas as flags", @"subtitle": @"Catálogo empacotado para busca.", @"dest": @"flags" },
            @{ @"kind": @"nav", @"title": @"Queries e configurações", @"subtitle": @"Query IDs e variáveis empacotadas.", @"dest": @"queries" },
        ],
        @[
            @{ @"kind": @"action", @"title": @"Validar arquivo mc_overrides.json", @"subtitle": @"Confirma o caminho obtido do runtime nativo.", @"action": @"ensure_mc_file" },
            @{ @"kind": @"action", @"title": @"A/B das flags de refresh/hash", @"subtitle": @"Experimento separado do A/B Employee do Centro de Diagnósticos.", @"action": @"qe_ab" },
            @{ @"kind": @"action", @"title": @"Limpar overrides runtime", @"subtitle": @"Ação destrutiva com confirmação.", @"action": @"clear" },
        ]
    ];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"Essencial";
        case 1: return @"Employee e laboratório";
        case 2: return @"MobileConfig";
        case 3: return @"Aparência e recursos";
        case 4: return @"Instrumentação avançada";
        case 5: return @"Biblioteca de ferramentas";
        case 6: return @"Manutenção";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"Employee local não é identidade autenticada e não garante autorização do endpoint QE-info.";
    if (section == 4) return @"Hooks avançados devem ser testados individualmente. Salvo ≠ instalado ≠ invocado ≠ valor efetivo.";
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
        sw.on = FBTMCNativeProbeIsKey(sw.prefKey) ?
            FBTMCNativeProbeIsEnabled(sw.prefKey) :
            [[NSUserDefaults standardUserDefaults] boolForKey:sw.prefKey];
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
    if (FBTMCNativeProbeIsKey(sender.prefKey)) {
        NSString *reason = nil;
        BOOL ok = FBTMCNativeProbeSetEnabled(sender.prefKey, sender.isOn, &reason);
        sender.on = FBTMCNativeProbeIsEnabled(sender.prefKey);
        [self showInfoTitle:ok ? @"Probe MobileConfig" : @"Probe recusado"
                    message:reason ?: (sender.on ?
                        @"Ativo somente nesta sessão. Reproduza o fetch e exporte os diagnósticos." :
                        @"Desarmado. Os wrappers já instalados continuam encaminhando o original sem observação.")];
        return;
    }
    if ([sender.prefKey isEqualToString:FBTKeyMobileConfigFetchDiagnosticsEnabled] && !sender.isOn) {
        FBTMCNativeProbeDisableAll();
        FBTMobileConfigFetchDiagnosticsRecord(@"capture_paused", @{});
    }
    [FBTDefaults setBool:sender.isOn forKey:sender.prefKey];
    if ([sender.prefKey isEqualToString:FBTKeyMobileConfigRuntimeEnabled]) {
        FBTMobileConfigSetSessionActive(sender.isOn);
        if (sender.isOn) {
            FBTInstallMobileConfigRuntime();
            FBTInstallNativeMobileConfigContextCapture();
        }
        FBTMobileConfigReloadPrefs();
    }
    if ([sender.prefKey isEqualToString:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        if (sender.isOn) {
            FBTMobileConfigResponseCaptureInstall();
            FBTInstallMobileConfigDebugUIBootstrap();
            FBTMobileConfigFetchDiagnosticsRecord(@"capture_started", @{});
            [self showInfoTitle:@"QE-info diagnostics ativado"
                        message:@"Reproduza agora o fetch na tela nativa de parâmetros. Depois abra FBTweak → Runtime → MobileConfig Live → Fetch log. O arquivo fica em AppGroup/mobileconfig/fbt_fetch_diagnostics.json."];
        } else {
            [self.tableView reloadData]; // Session-only native probes are OFF in the UI too.
            [self showInfoTitle:@"QE-info diagnostics pausado"
                        message:@"Novos eventos não serão registrados. Os logs existentes permanecem no AppGroup."];
        }
    }
    if ([sender.prefKey isEqualToString:FBTKeyMobileConfigCaptureEnabled] ||
        [sender.prefKey isEqualToString:FBTKeyMobileConfigOverridesEnabled]) {
        FBTMobileConfigReloadPrefs();
    }
    if ([sender.prefKey isEqualToString:FBTKeyRuntimeBoolBrowserEnabled]) {
        FBTRuntimeBoolReloadPrefs();
        if (sender.isOn) FBTRuntimeBoolReinstallPersistedHooks();
    }
    if ([sender.prefKey isEqualToString:FBTKeyDogfoodSweepEnabled] ||
        [sender.prefKey isEqualToString:FBTKeyInternalDebugSweepEnabled]) {
        NSString *mode = [sender.prefKey isEqualToString:FBTKeyDogfoodSweepEnabled] ? @"dogfood" : @"internaldebug";
        if (!sender.isOn) {
            FBTRuntimeBoolClearSweep(mode);
            [self showInfoTitle:@"Sweep desativado"
                        message:@"Overrides deste sweep foram removidos. Trampolines previamente instalados continuam no processo, mas retornam ao comportamento original. Outras forças não foram alteradas."];
        } else {
            BOOL browserWasOff = ![FBTDefaults boolForKey:FBTKeyRuntimeBoolBrowserEnabled];
            if (browserWasOff) [FBTDefaults setBool:YES forKey:FBTKeyRuntimeBoolBrowserEnabled];
            FBTRuntimeBoolReloadPrefs();
            NSUInteger n = FBTRuntimeBoolInstallSweep(mode, YES, 160);
            NSDictionary *stats = FBTRuntimeBoolSweepStats()[mode] ?: @{};
            if (!n) {
                [FBTDefaults setBool:NO forKey:sender.prefKey];
                sender.on = NO;
            }
            [self showInfoTitle:n ? @"Sweep aplicado" : @"Nenhum hook instalado"
                        message:[NSString stringWithFormat:
                            @"Instalados: %lu. Rejeitados: %@. Preservados de outros donos: %@.%@\nA instalação não prova invocação. Consulte o Runtime BOOL para ver contador e valor efetivo.",
                            (unsigned long)n, stats[@"rejected"] ?: @0, stats[@"skipped_other_owner"] ?: @0,
                            browserWasOff ? @"\nRuntime BOOL Browser foi habilitado por dependência." : @""]];
        }
        [self.tableView reloadData];
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

- (void)applyQEFlagABTest:(NSString *)variant {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    FBTMCState legacyState;
    FBTMCState hashState;

    if ([prefs boolForKey:FBTQESnapshotValidKey]) {
        legacyState = (FBTMCState)[prefs integerForKey:FBTQESnapshotLegacyStateKey];
        hashState = (FBTMCState)[prefs integerForKey:FBTQESnapshotBuiltinHashStateKey];
    } else {
        legacyState = [FBTMCOverridesFile stateForConfig:FBTQELegacyConfigKey paramIdx:2];
        hashState = [FBTMCOverridesFile stateForConfig:FBTQEBuiltinHashConfigKey paramIdx:4];
        [prefs setInteger:legacyState forKey:FBTQESnapshotLegacyStateKey];
        [prefs setInteger:hashState forKey:FBTQESnapshotBuiltinHashStateKey];
        [prefs setBool:YES forKey:FBTQESnapshotValidKey];
        [prefs synchronize];
    }

    // Reapply the pre-test baseline first so switching A/B cannot leave both
    // candidates disabled at once. SYS removes the explicit entry.
    [FBTMCOverridesFile setState:legacyState forConfig:FBTQELegacyConfigKey
                        paramIdx:2 name:@"mobileconfig_use_legacy_refresh"];
    [FBTMCOverridesFile setState:hashState forConfig:FBTQEBuiltinHashConfigKey
                        paramIdx:4 name:@"use_builtin_query_hash"];

    NSString *testedFlag = @"baseline (nenhuma flag alterada)";
    if ([variant isEqualToString:@"legacy"]) {
        [FBTMCOverridesFile setState:FBTMCStateOff forConfig:FBTQELegacyConfigKey
                            paramIdx:2 name:@"mobileconfig_use_legacy_refresh"];
        testedFlag = @"mobileconfig_use_legacy_refresh";
    } else if ([variant isEqualToString:@"hash"]) {
        [FBTMCOverridesFile setState:FBTMCStateOff forConfig:FBTQEBuiltinHashConfigKey
                            paramIdx:4 name:@"use_builtin_query_hash"];
        testedFlag = @"use_builtin_query_hash";
    }

    FBTMCState currentLegacy = [FBTMCOverridesFile stateForConfig:FBTQELegacyConfigKey paramIdx:2];
    FBTMCState currentHash = [FBTMCOverridesFile stateForConfig:FBTQEBuiltinHashConfigKey paramIdx:4];
    BOOL stateWritten = [FBTMCOverridesFile fileExists] &&
        (currentLegacy == ([variant isEqualToString:@"legacy"] ? FBTMCStateOff : legacyState)) &&
        (currentHash == ([variant isEqualToString:@"hash"] ? FBTMCStateOff : hashState));
    if (!stateWritten) {
        [self showInfoTitle:@"Não consegui confirmar o ajuste"
                    message:[NSString stringWithFormat:@"O estado esperado não foi relido de mc_overrides.json.\nPath: %@\nLegacy: %@ · query hash: %@\nNão execute a comparação até corrigir o path do arquivo.",
                        [FBTMCOverridesFile path] ?: @"unknown",
                        FBTMCStateLabel(currentLegacy), FBTMCStateLabel(currentHash)]];
        return;
    }
    NSString *message = [NSString stringWithFormat:
        @"Teste isolado gravado em mc_overrides.json.\n\n"
         @"mobileconfig_use_legacy_refresh: %@\n"
         @"use_builtin_query_hash: %@\n\n"
         @"Reinicie o Facebook, ative o log QE-info e execute Force name download. Compare name_download_completed, qe_info_request_returned e query_hash_state.\n\n"
         @"Importante: isso confirma apenas o estado gravado no arquivo, não que a versão atual do app reconheça esses parâmetros. No AppGroup analisado, os dois configs não apareceram nos sidecars ativos de nomes; se não houver mudança, o próximo passo é confirmar resolução/schema, não desligar outras flags em lote.\n\n"
         @"Flag isolada neste teste: %@%@",
        FBTMCStateLabel(currentLegacy), FBTMCStateLabel(currentHash), testedFlag,
        ([variant isEqualToString:@"legacy"] && legacyState == FBTMCStateOff) ?
            @"\nATENÇÃO: legacy refresh já estava OFF na linha de base; a intervenção não muda esse valor." :
        (([variant isEqualToString:@"hash"] && hashState == FBTMCStateOff) ?
            @"\nATENÇÃO: builtin query hash já estava OFF na linha de base; a intervenção não muda esse valor." : @"")];
    [self showInfoTitle:@"Teste A/B QE-info preparado" message:message];
}

- (void)restoreQEFlagABTest {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if (![prefs boolForKey:FBTQESnapshotValidKey]) {
        [self showInfoTitle:@"Sem snapshot A/B" message:@"Nenhum estado anterior foi salvo por este teste; não alterei o arquivo."];
        return;
    }

    FBTMCState legacyState = (FBTMCState)[prefs integerForKey:FBTQESnapshotLegacyStateKey];
    FBTMCState hashState = (FBTMCState)[prefs integerForKey:FBTQESnapshotBuiltinHashStateKey];
    [FBTMCOverridesFile setState:legacyState forConfig:FBTQELegacyConfigKey
                        paramIdx:2 name:@"mobileconfig_use_legacy_refresh"];
    [FBTMCOverridesFile setState:hashState forConfig:FBTQEBuiltinHashConfigKey
                        paramIdx:4 name:@"use_builtin_query_hash"];

    FBTMCState restoredLegacy = [FBTMCOverridesFile stateForConfig:FBTQELegacyConfigKey paramIdx:2];
    FBTMCState restoredHash = [FBTMCOverridesFile stateForConfig:FBTQEBuiltinHashConfigKey paramIdx:4];
    if (![FBTMCOverridesFile fileExists] || restoredLegacy != legacyState || restoredHash != hashState) {
        [self showInfoTitle:@"Restauração não confirmada"
                    message:[NSString stringWithFormat:@"O estado anterior não foi relido do arquivo. O snapshot foi mantido para tentar novamente.\nPath: %@\nLegacy: %@ · query hash: %@",
                        [FBTMCOverridesFile path] ?: @"unknown",
                        FBTMCStateLabel(restoredLegacy), FBTMCStateLabel(restoredHash)]];
        return;
    }

    [prefs removeObjectForKey:FBTQESnapshotValidKey];
    [prefs removeObjectForKey:FBTQESnapshotLegacyStateKey];
    [prefs removeObjectForKey:FBTQESnapshotBuiltinHashStateKey];
    [prefs synchronize];

    [self showInfoTitle:@"Overrides restaurados"
                message:[NSString stringWithFormat:
                    @"Estado anterior restaurado em mc_overrides.json.\n"
                     @"mobileconfig_use_legacy_refresh: %@\n"
                     @"use_builtin_query_hash: %@",
                    FBTMCStateLabel(legacyState), FBTMCStateLabel(hashState)]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.sections[indexPath.section][indexPath.row];
    NSString *kind = item[@"kind"];
    if ([kind isEqualToString:@"nav"]) {
        NSString *dest = item[@"dest"];
        UIViewController *vc = nil;
        if ([dest isEqualToString:@"localconfig"]) vc = [[FBTLocalConfigViewController alloc] initWithSearchQuery:@""];
        else if ([dest isEqualToString:@"namesdiagnostic"]) vc = [[FBTNamesDiagnosticsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"networkinspector"]) vc = [[FBTNetworkInspectorViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"mobileconfig"]) vc = [[FBTMobileConfigViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"bool"]) vc = [[FBTSymbolsBrowserViewController alloc] initWithMode:FBTCSymbolsBrowserModeObjCMethods];
        else if ([dest isEqualToString:@"boollive"]) vc = [[FBTRuntimeBoolViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"hookaudit"]) vc = [[FBTHookAuditViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"livetrace"]) vc = [[FBTNativeTraceViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest hasPrefix:@"feat:"]) vc = [[FBTFeatureParamsViewController alloc] initWithFeatureId:[dest substringFromIndex:5]];
        else if ([dest isEqualToString:@"headline"]) { FBTFlagDumpViewController *f = [[FBTFlagDumpViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; f.headlineOnly = YES; vc = f; }
        else if ([dest isEqualToString:@"flags"]) { FBTFlagDumpViewController *f = [[FBTFlagDumpViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; f.headlineOnly = NO; vc = f; }
        else if ([dest isEqualToString:@"queries"]) vc = [[FBTQueryConfigViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        if (vc) [self.navigationController pushViewController:vc animated:YES];
    } else if ([kind isEqualToString:@"action"]) {
        NSString *action = item[@"action"];
        if ([action isEqualToString:@"native"]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"FBTRequestOpenNativeInternalSettings" object:nil];
        } else if ([action isEqualToString:@"whitehat"]) {
            FBTOpenNativeWhitehatSettings();
        } else if ([action isEqualToString:@"ensure_mc_file"]) {
            BOOL ok = FBTNativeMobileConfigEnsureOverridesFile();
            NSString *path = FBTNativeMobileConfigOverridesFilePath() ?: @"path ainda não capturado";
            UIAlertController *a = [UIAlertController alertControllerWithTitle:ok ? @"Arquivo pronto" : @"Sem path nativo" message:[NSString stringWithFormat:@"%@\n%@", path, FBTNativeMobileConfigStatus() ?: @""] preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        } else if ([action isEqualToString:@"qe_ab"]) {
            FBTMCState legacyState = [FBTMCOverridesFile stateForConfig:FBTQELegacyConfigKey paramIdx:2];
            FBTMCState hashState = [FBTMCOverridesFile stateForConfig:FBTQEBuiltinHashConfigKey paramIdx:4];
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Teste A/B QE-info"
                message:[NSString stringWithFormat:
                    @"Estado atual gravado no arquivo:\nlegacy refresh: %@\nbuiltin query hash: %@\n\nEscolha uma hipótese. O teste anterior não é combinado com o atual; use Restaurar para voltar ao estado salvo.",
                    FBTMCStateLabel(legacyState), FBTMCStateLabel(hashState)]
                preferredStyle:UIAlertControllerStyleActionSheet];
            [a addAction:[UIAlertAction actionWithTitle:@"0 — Baseline (sem alteração)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
                [self applyQEFlagABTest:@"baseline"];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"A — legacy refresh OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
                [self applyQEFlagABTest:@"legacy"];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"B — builtin query hash OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
                [self applyQEFlagABTest:@"hash"];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Restaurar estado anterior" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
                [self restoreQEFlagABTest];
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            a.popoverPresentationController.sourceView = cell;
            a.popoverPresentationController.sourceRect = cell.bounds;
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
    UIBarButtonItem *diagnostics = [[UIBarButtonItem alloc] initWithTitle:@"Fetch log" style:UIBarButtonItemStylePlain target:self action:@selector(showFetchDiagnostics)];
    UIBarButtonItem *plistAudit = [[UIBarButtonItem alloc] initWithTitle:@"Plist audit" style:UIBarButtonItemStylePlain target:self action:@selector(showOverridesPlistAudit)];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadSnapshot)];
    self.navigationItem.rightBarButtonItems = @[diagnostics, plistAudit, refresh];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Buscar key, config ou param";
    self.navigationItem.searchController = self.searchController;
    // Ação manual pós-launch: evita o watchdog do ctor, mas faz o browser
    // funcionar quando o usuário abre a tela. Inclui RCTMobileConfigNative e
    // readers ObjC genéricos do novo FBReactNativeProductsFramework.
    FBTMobileConfigSetSessionActive(YES);
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


- (void)showOverridesPlistAudit {
    NSDictionary *report = FBTMCPreferencesAuditRun() ?: @{};
    NSArray<NSDictionary *> *mismatches = [report[@"mismatches"] isKindOfClass:[NSArray class]] ? report[@"mismatches"] : @[];
    NSMutableString *summary = [NSMutableString stringWithFormat:
        @"Bundle ID: %@\nOverride: %@\nOverride JSON: %@ · file %@\nEffective plist: %@\n\n"
         @"Rows inspected: %@\nMatch: %@ · Mismatch: %@\nNot represented in plist: %@\nPlist entries without value: %@\nMalformed: %@\nPlist candidates found: %@ · startup configs: %@\n\n",
        report[@"bundle_id"] ?: @"unknown",
        report[@"override_file_path"] ?: @"not_found",
        [report[@"override_json_valid"] boolValue] ? @"valid" : @"invalid / unavailable",
        [report[@"override_file_exists"] boolValue] ? @"exists" : @"missing",
        report[@"preferences_plist_path"] ?: @"not_found",
        report[@"override_rows_total"] ?: @0,
        report[@"values_matching_plist"] ?: @0,
        report[@"values_mismatching_plist"] ?: @0,
        report[@"parameters_not_represented_in_plist"] ?: @0,
        report[@"plist_entries_without_v"] ?: @0,
        report[@"malformed_override_rows"] ?: @0,
        report[@"preferences_plist_candidates_found"] ?: @0,
        report[@"startup_config_entries"] ?: @0];
    if (mismatches.count) {
        [summary appendString:@"\nDivergências (override → plist):\n"];
        NSUInteger limit = MIN(mismatches.count, 18);
        for (NSUInteger i = 0; i < limit; i++) {
            NSDictionary *item = mismatches[i];
            [summary appendFormat:@"• %@.%@: %@ → %@\n",
                item[@"config"] ?: @"?",
                item[@"param"] ?: @"?",
                item[@"override_value"] ?: @"?",
                item[@"plist_value"] ?: @"?"];
        }
        if (mismatches.count > limit) {
            [summary appendFormat:@"… mais %lu divergências; copie o JSON completo.\n",
                (unsigned long)(mismatches.count - limit)];
        }
    } else {
        [summary appendString:@"\nNenhuma divergência entre as entradas comparáveis encontradas."];
    }
    [summary appendString:@"\n\n‘Não representado no plist’ não é contado como divergência: significa que esse config.param não existe no mapa FBMobileConfigStartupConfigs selecionado. A auditoria compara estado persistido; sozinha, não prova que um reader em runtime consumiu o override."];
    if ([report[@"audit_report_path"] isKindOfClass:[NSString class]]) {
        [summary appendFormat:@"\n\nJSON completo: %@", report[@"audit_report_path"]];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"mc_overrides ↔ Preferences plist"
                                                                   message:summary
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copiar JSON completo" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        if ([NSJSONSerialization isValidJSONObject:report]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
            NSString *json = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            if (json.length) [UIPasteboard generalPasteboard].string = json;
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Fechar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFetchDiagnostics {
    [self.navigationController pushViewController:[[FBTNamesDiagnosticsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}

- (void)showLegacyFetchDiagnostics {
    NSDictionary *report = FBTMobileConfigFetchDiagnosticsSnapshot();
    NSArray *events = [report[@"events"] isKindOfClass:[NSArray class]] ? report[@"events"] : @[];
    NSDictionary *last = [events.lastObject isKindOfClass:[NSDictionary class]] ? events.lastObject : @{};
    NSDictionary *lastFetch = nil;
    NSDictionary *lastError = nil;
    NSDictionary *lastSelection = nil;
    NSDictionary *lastHook = nil;
    NSInteger lastSelectionIndex = -1;
    for (NSDictionary *event in [events.reverseObjectEnumerator allObjects]) {
        if (!lastFetch && [event[@"event"] isEqualToString:@"qe_info_request_returned"]) lastFetch = event;
        if (!lastSelection && [event[@"event"] isEqualToString:@"selection_started"]) lastSelection = event;
        if (!lastHook && [event[@"event"] isEqualToString:@"qe_info_import_hook"]) lastHook = event;
        if (lastFetch && lastSelection && lastHook) break;
    }
    if (lastSelection) {
        lastSelectionIndex = [events indexOfObjectIdenticalTo:lastSelection];
        lastFetch = nil;
        for (NSUInteger i = (NSUInteger)MAX(lastSelectionIndex, 0); i < events.count; i++) {
            NSDictionary *event = events[i];
            if ([event[@"event"] isEqualToString:@"qe_info_request_returned"]) lastFetch = event;
            if ([event[@"event"] isEqualToString:@"native_network_error"] || [event[@"event"] isEqualToString:@"qe_info_failure_alert"]) lastError = event;
        }
    }
    NSDictionary *cache = [report[@"cache_state"] isKindOfClass:[NSDictionary class]] ? report[@"cache_state"] : @{};
    NSArray *qce = [cache[@"qce_metadata"] isKindOfClass:[NSArray class]] ? cache[@"qce_metadata"] : @[];
    NSArray *dumps = [cache[@"response_dumps"] isKindOfClass:[NSArray class]] ? cache[@"response_dumps"] : @[];
    BOOL enabled = [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
    NSMutableString *summary = [NSMutableString stringWithFormat:@"Captura: %@\nEventos capturados: %lu\nÚltimo evento: %@ · %@\nParâmetro/config: %@ / %@\nBackend type: %@ · contextos vivos: %@\n",
        enabled ? @"LIGADA" : @"DESLIGADA",
        (unsigned long)events.count,
        last[@"event"] ?: @"nenhum",
        last[@"time_utc"] ?: @"—",
        lastSelection[@"param"] ?: @"—",
        lastSelection[@"config"] ?: @"—",
        lastSelection[@"backend_type"] ?: @"—",
        lastSelection[@"context_count"] ?: @"—"];
    [summary appendFormat:@"Hook QE-info: %@\n",
        lastHook ? ([lastHook[@"hook_installed"] boolValue] ? @"INSTALADO" : @"NÃO DISPONÍVEL") : @"sem registro"];
    if (lastFetch) {
        [summary appendFormat:@"\nRetorno nativo: %@ · duração: %@ ms\n",
            [lastFetch[@"fetch_result"] boolValue] ? @"SUCESSO" : @"FALHA",
            lastFetch[@"duration_ms"] ?: @"?"];
    }
    if (lastError) {
        [summary appendFormat:@"Último erro: %@ · código %@ · HTTP %@\n%@\n",
            lastError[@"error_domain"] ?: @"QE-info/UI",
            lastError[@"error_code"] ?: @"—",
            lastError[@"http_status"] ?: @"—",
            lastError[@"message"] ?: lastError[@"alert_message"] ?: lastError[@"alert"] ?: @"sem mensagem"];
    }
    NSDictionary *bodyStatus = FBTMobileConfigResponseCaptureStatus();
    [summary appendFormat:@"\nRaw response capture: NSURLSession %@ · Tigon %@ · state %@ · payload %@\n",
        [bodyStatus[@"hook_installed"] boolValue] ? @"INSTALLED" : @"NOT INSTALLED",
        [bodyStatus[@"tigon_hooks_installed"] boolValue] ? @"INSTALLED" : @"NOT INSTALLED",
        bodyStatus[@"last_capture_status"] ?: @"unknown",
        bodyStatus[@"last_payload_file"] ?: @"none"];
    [summary appendFormat:@"Corpos salvos (todos os transports): %@ · respostas Tigon concluídas: %@ · contextos Tigon ativos: %@\n",
        bodyStatus[@"captured_body_count"] ?: @0,
        bodyStatus[@"tigon_completed_response_count"] ?: @0,
        bodyStatus[@"tigon_context_count"] ?: @0];
    [summary appendFormat:@"MobileConfig fetcher direto: %@ · requests %@ · respostas %@ · falhas %@\n",
        [bodyStatus[@"native_mc_fetcher_installed"] boolValue] ? @"INSTALLED" : (bodyStatus[@"native_mc_fetcher_failure"] ?: @"indisponível"),
        bodyStatus[@"native_mc_requests"] ?: @0, bodyStatus[@"native_mc_responses"] ?: @0, bodyStatus[@"native_mc_failures"] ?: @0];
    NSDictionary *nativeHooks = report[@"native_hooks"];
    [summary appendFormat:@"Hooks QE/nomes disponíveis agora: %@ / %@\nContextos: %@\n", nativeHooks[@"qe_info_hook_available"] ?: @NO,
        nativeHooks[@"name_download_hook_available"] ?: @NO, nativeHooks[@"contexts"] ?: @{}];
    NSDictionary *lastNameDownload = nil;
    NSDictionary *lastResponseBody = nil;
    NSDictionary *lastRequest = nil;
    for (NSDictionary *event in [events.reverseObjectEnumerator allObjects]) {
        if (!lastNameDownload && ([event[@"event"] isEqualToString:@"name_download_completed"] ||
                                  [event[@"event"] isEqualToString:@"name_download_started"])) lastNameDownload = event;
        if (!lastResponseBody && ([event[@"event"] isEqualToString:@"network_response_body_captured"] ||
                                  [event[@"event"] isEqualToString:@"network_response_body_skipped"] ||
                                  [event[@"event"] isEqualToString:@"tigon_response_body_unavailable"])) lastResponseBody = event;
        if (!lastRequest && ([event[@"event"] isEqualToString:@"native_mc_fetch_started"] ||
                             [event[@"event"] isEqualToString:@"network_request_candidate"] ||
                             [event[@"event"] isEqualToString:@"tigon_request_started"])) lastRequest = event;
        if (lastNameDownload && lastResponseBody && lastRequest) break;
    }
    if (lastNameDownload) {
        [summary appendFormat:@"Force name download: %@ · force %@ · success %@\n",
            lastNameDownload[@"event"] ?: @"unknown",
            lastNameDownload[@"force"] ?: @"—",
            lastNameDownload[@"download_success"] ?: @"pending"];
    }
    NSDictionary *flagStateEvent = lastNameDownload ?: lastFetch;
    if (flagStateEvent) {
        [summary appendFormat:@"Override file state at event (not proof of runtime resolution): legacy refresh %@ · builtin query hash %@\n",
            flagStateEvent[@"legacy_refresh_override_file_state"] ?: @"not recorded",
            flagStateEvent[@"builtin_query_hash_override_file_state"] ?: @"not recorded"];
    }
    if (lastRequest) {
        [summary appendFormat:@"Request boundary: %@ %@ · query_hash %@ (%@ chars) · one_query_hash %@ (%@ chars)\n",
            lastRequest[@"request_method"] ?: @"?",
            [NSString stringWithFormat:@"%@%@", lastRequest[@"request_host"] ?: @"", lastRequest[@"request_path"] ?: @""],
            lastRequest[@"query_hash_state"] ?: @"missing",
            lastRequest[@"query_hash_length"] ?: @0,
            lastRequest[@"one_query_hash_state"] ?: @"missing",
            lastRequest[@"one_query_hash_length"] ?: @0];
    }
    if (lastResponseBody) {
        [summary appendFormat:@"Last response body: %@ · transport %@ · HTTP %@ · %@ bytes · %@\n",
            lastResponseBody[@"body_capture_status"] ?: lastResponseBody[@"event"] ?: @"unknown",
            lastResponseBody[@"transport"] ?: @"unknown",
            ([lastResponseBody[@"http_status"] integerValue] > 0) ? lastResponseBody[@"http_status"] : @"not exposed",
            lastResponseBody[@"response_bytes"] ?: @0,
            lastResponseBody[@"payload_file"] ?: @"no file saved"];
    }
    [summary appendString:@"\nQE-info cache:\n"];
    if (!qce.count) [summary appendString:@"  nenhum store QCE encontrado\n"];
    [qce enumerateObjectsUsingBlock:^(NSDictionary *store, NSUInteger idx, __unused BOOL *stop) {
        [summary appendFormat:@"  store %lu: gen %@ · nomes %@ · atualizado %@\n",
            (unsigned long)(idx + 1), store[@"latest_generation"] ?: @"?",
            store[@"param_name_count"] ?: @"?", store[@"latest_file_utc"] ?: @"?"];
    }];
    [summary appendString:@"Resposta MobileConfig mais recente (se exportada):\n"];
    if (!dumps.count) [summary appendString:@"  nenhum dump disponível\n"];
    [dumps enumerateObjectsUsingBlock:^(NSDictionary *dump, NSUInteger idx, __unused BOOL *stop) {
        [summary appendFormat:@"  dump %lu: configs %@ · QCE entries %@ · query hash %@\n",
            (unsigned long)(idx + 1), dump[@"config_count"] ?: @"?",
            dump[@"qce_entry_count"] ?: @"?",
            [dump[@"has_query_hash"] boolValue] ? @"presente" : @"ausente"];
    }];
    [summary appendString:@"\nRelatório JSON redigido persistido em AppGroup/mobileconfig/fbt_fetch_diagnostics.json.\nO fetch remoto pode falhar por rede/permissão/backend; esta tela registra o estado local, não inventa sucesso."];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Diagnóstico de fetch" message:summary preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copiar JSON completo" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = FBTMobileConfigFetchDiagnosticsJSON();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copiar última resposta bruta" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *body = FBTMobileConfigResponseCaptureLastBodyString();
        if (body.length) {
            [UIPasteboard generalPasteboard].string = body;
        } else {
            FBTLog(@"No captured text response body available; inspect AppGroup/mobileconfig/fbt_fetch_payloads and capture status.");
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Ver última resposta bruta" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *body = FBTMobileConfigResponseCaptureLastBodyString();
        if (!body.length) body = @"Nenhum corpo de resposta textual foi capturado. Veja o estado do hook, o evento network_request_candidate e o arquivo do App Group.";
        NSString *preview = body.length > 4500
            ? [[body substringToIndex:4500] stringByAppendingString:@"\n\n[Prévia limitada; use Copiar última resposta bruta para o corpo completo.]"]
            : body;
        UIAlertController *detail = [UIAlertController alertControllerWithTitle:@"Última resposta bruta" message:preview preferredStyle:UIAlertControllerStyleAlert];
        [detail addAction:[UIAlertAction actionWithTitle:@"Copiar corpo completo" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *copyAction) {
            NSString *complete = FBTMobileConfigResponseCaptureLastBodyString();
            if (complete.length) [UIPasteboard generalPasteboard].string = complete;
        }]];
        [detail addAction:[UIAlertAction actionWithTitle:@"Fechar" style:UIAlertActionStyleCancel handler:nil]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:detail animated:YES completion:nil];
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Fechar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
    if (! [type isEqualToString:@"bool"] && [@[@"int64", @"double", @"string"] containsObject:type]) {
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Force %@…", type] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [self promptValueForKey:key type:type title:[@"Force " stringByAppendingString:type]];
        }]];
    }
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
        if ([type isEqualToString:@"int64"] || [type isEqualToString:@"double"]) {
            NSString *trimmed = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            const char *start = trimmed.UTF8String; char *end = NULL; errno = 0;
            if ([type isEqualToString:@"int64"]) value = @(strtoll(start, &end, 0));
            else value = @(strtod(start, &end));
            if (errno == ERANGE || end == start || *end != '\0' ||
                ([type isEqualToString:@"double"] && !isfinite([value doubleValue]))) return;
        }
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
    self.title = @"Runtime BOOL · Métodos e ivars";
    self.entityMode = 0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 100;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:FBTCellID];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Trace" style:UIBarButtonItemStylePlain target:self action:@selector(showNativeTrace)],
        [[UIBarButtonItem alloc] initWithTitle:@"Buscar" style:UIBarButtonItemStylePlain target:self action:@selector(runSearch)]
    ];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Classe/selector/image: dogfood, FBShared, main-exec…";
    self.navigationItem.searchController = self.searchController;
    UISegmentedControl *types = [[UISegmentedControl alloc] initWithItems:@[@"Métodos BOOL", @"Ivars BOOL"]];
    types.selectedSegmentIndex = 0;
    types.accessibilityIdentifier = @"fbt.boolBrowser.entityType";
    [types addTarget:self action:@selector(entityTypeChanged:) forControlEvents:UIControlEventValueChanged];
    types.frame = CGRectMake(0, 0, 320, 45);
    self.tableView.tableHeaderView = types;
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

- (void)entityTypeChanged:(UISegmentedControl *)sender {
    self.entityMode = sender.selectedSegmentIndex;
    [self runSearch];
}
- (void)showNativeTrace {
    [self.navigationController pushViewController:[[FBTNativeTraceViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
- (void)runSearch {
    NSString *q = self.searchController.searchBar.text ?: @"";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *result = self.entityMode == 1 ? FBTRuntimeBoolSearchIvars(q, 0) : FBTRuntimeBoolSearch(q, 0);
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
        cfg.text = @"Nenhuma entrada BOOL encontrada";
        cfg.secondaryText = @"Enumeração por encoding Objective-C real, sem categorias pré-selecionadas. Ivars booleanas são dados, não métodos interceptáveis.";
        cfg.secondaryTextProperties.numberOfLines = 0;
        cell.contentConfiguration = cfg;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    NSDictionary *e = self.filtered[indexPath.row];
    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    // Never truncate the exact selector: category tags are secondary metadata.
    BOOL ivar = [e[@"entityType"] isEqualToString:@"ivar"];
    cfg.text = ivar ? [NSString stringWithFormat:@"%@.%@ (ivar)",e[@"class"] ?: @"?",e[@"selector"] ?: @"?"] :
        [NSString stringWithFormat:@"%@[%@ %@]",
        [e[@"classMethod"] boolValue] ? @"+" : @"-", e[@"class"] ?: @"?", e[@"selector"] ?: @"?"];
    cfg.textProperties.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium];
    cfg.textProperties.numberOfLines = 0;
    NSString *force = [e[@"forced"] boolValue] ? [NSString stringWithFormat:@" · FORCE %@", FBTBoolText([e[@"force"] boolValue])] : ([e[@"observing"] boolValue] ? @" · OBSERVE" : @"");
    NSString *hookState = [e[@"entityType"] isEqualToString:@"ivar"] ? @"Sem hook: armazenamento de dados, não método" : e[@"installState"] ?: @"not_requested";
    id original = e[@"observedOriginal"];
    id effective = e[@"observedEffective"];
    NSString *originalLabel = original && original != [NSNull null] ? FBTBoolText([original boolValue]) : @"não medido";
    NSString *effectiveLabel = effective && effective != [NSNull null] ? FBTBoolText([effective boolValue]) : @"não medido";
    cfg.secondaryText = [NSString stringWithFormat:@"%@ · %@%@\n%@\nHook: %@ · Original: %@ · Efetivo: %@ · Chamadas: %@",
                         e[@"category"] ?: @"BOOL", e[@"imageKind"] ?: @"unknown", force, e[@"signature"] ?: @"BOOL",
                         hookState, originalLabel, effectiveLabel, e[@"invocationCount"] ?: @0];
    cfg.secondaryTextProperties.numberOfLines = 0;
    cfg.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    cell.contentConfiguration = cfg;
    cell.accessoryType = [e[@"forced"] boolValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)reportRuntimeHookStatus:(NSDictionary *)entry action:(NSString *)action {
    NSString *key = entry[@"key"] ?: @"";
    BOOL installed = FBTRuntimeBoolHookInstalledForKey(key);
    NSDictionary *persisted = FBTRuntimeBoolOverridesSnapshot()[key];
    BOOL saved = [persisted isKindOfClass:NSDictionary.class];
    NSString *state = installed ? @"Hook instalado; execução ainda não comprovada." :
        (saved ? @"Preferência salva, mas hook pendente/recusado. Não está aplicando." :
                 @"Nenhum override ativo para esta entrada.");
    NSString *text = [NSString stringWithFormat:
        @"%@\n\n%@[%@ %@]\n%@\n\nSalvo: %@ · instalado: %@\n\nConfirme a execução no contador de chamadas e no valor efetivo do browser. Hooks sem ABI compatível são recusados.",
        action, [entry[@"classMethod"] boolValue] ? @"+" : @"-", entry[@"class"] ?: @"?",
        entry[@"selector"] ?: @"?", state, saved ? @"SIM" : @"NÃO", installed ? @"SIM" : @"NÃO"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Estado do hook" message:text preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Entendi" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.filtered.count) return;
    NSDictionary *e = self.filtered[indexPath.row];
    NSString *msg = [NSString stringWithFormat:@"Função: %@[%@ %@]\nFramework: %@\nImagem: %@\nAssinatura: %@\nHook: %@\nChamadas: %@\nValor original: %@\nValor efetivo: %@\n\nSalvar uma força não comprova execução. Verifique chamadas/efetivo após acionar o recurso nativo.",
        [e[@"classMethod"] boolValue] ? @"+" : @"-", e[@"class"] ?: @"",e[@"selector"] ?: @"",
        e[@"imageKind"] ?: @"unknown",e[@"image"] ?: @"",e[@"signature"] ?: @"BOOL",
        e[@"installState"] ?: @"não solicitado", e[@"invocationCount"] ?: @0,
        e[@"observedOriginal"] ?: @"não observado",e[@"observedEffective"] ?: @"não observado"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Inspeção de hook BOOL" message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    if ([e[@"entityType"] isEqualToString:@"ivar"]) {
        [a addAction:[UIAlertAction actionWithTitle:@"Copiar metadados" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { UIPasteboard.generalPasteboard.string = msg; }]];
    } else {
    [a addAction:[UIAlertAction actionWithTitle:@"Observar (sem forçar)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { FBTRuntimeBoolObserve(e); [self runSearch]; [self reportRuntimeHookStatus:e action:@"Observação"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { FBTRuntimeBoolSetOverride(e, YES); [self runSearch]; [self reportRuntimeHookStatus:e action:@"Force ON"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { FBTRuntimeBoolSetOverride(e, NO); [self runSearch]; [self reportRuntimeHookStatus:e action:@"Force OFF"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Desfazer override" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) { FBTRuntimeBoolClearOverride(e); [self runSearch]; [self reportRuntimeHookStatus:e action:@"Override removido"]; }]];
    }
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

