#import "FBTSettingsViewController.h"
#import "FBTLocalConfigViewController.h"
#import "FBTNamesDiagnosticsViewController.h"
#import "FBTNetworkInspectorViewController.h"
#import "FBTNativeTraceViewController.h"
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
#import "../Runtime/FBTDogFoodNative.h"
#import "../Runtime/FBTNativeInternalSurfaces.h"
#import "../Features/ReactNative/FBTReactNativeInternal.h"
#include <stdlib.h>
#include <errno.h>
#include <math.h>

extern void FBTInstallLiquidGlassHooks(void);
extern void FBTOpenNativeWhitehatSettings(void);
extern void FBTSettingsGateDidSwitch(NSString *key, BOOL enabled);

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
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (@available(iOS 26.0, *)) {
        // Use the system default Glass. Do NOT set any custom appearance on iOS26.
    } else {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithDefaultBackground];
        bar.standardAppearance = appearance;
        bar.scrollEdgeAppearance = appearance;
        bar.compactAppearance = appearance;
    }
    bar.prefersLargeTitles = YES;
}

// A single native glass hero is sufficient. System rows, switches, and the
// navigation bar get their appearance from UIKit. Avoid glass on every cell.
static UIView *FBTGlassOverviewHeader(CGFloat width) {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 134)];
    container.backgroundColor = [UIColor clearColor];
    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) effect = [UIGlassEffect new];
    else effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.frame = CGRectMake(16, 12, MAX(0, width - 32), 108);
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    glass.layer.cornerRadius = 24;
    glass.clipsToBounds = YES;
    [container addSubview:glass];

    UILabel *heading = [UILabel new];
    heading.text = @"FBTweak";
    heading.textColor = [UIColor labelColor];
    heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    heading.adjustsFontForContentSizeCategory = YES;
    UILabel *caption = [UILabel new];
    caption.text = @"Acessos nativos, flags locais e diagnósticos organizados por área.";
    caption.textColor = [UIColor secondaryLabelColor];
    caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    caption.adjustsFontForContentSizeCategory = YES;
    caption.numberOfLines = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[heading, caption]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [glass.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-18],
        [stack.centerYAnchor constraintEqualToAnchor:glass.contentView.centerYAnchor]
    ]];
    return container;
}

static NSArray<NSDictionary *> *FBTMenuRows(NSArray<NSArray<NSDictionary *> *> *catalog,
                                            NSString *field, NSArray<NSString *> *values) {
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    for (NSString *value in values) {
        for (NSArray<NSDictionary *> *section in catalog) {
            for (NSDictionary *row in section) {
                if ([row[field] isEqualToString:value]) [matches addObject:row];
            }
        }
    }
    return matches;
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
@property (nonatomic, copy) NSString *menuGroup;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
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
    // Do not override the system Liquid Glass navigation appearance on iOS 26.
    nav.navigationBar.prefersLargeTitles = YES;
    return nav;
}
@end

@implementation FBTSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL isRoot = self.menuGroup.length == 0;
    if (isRoot) self.title = @"FBTweak";
    self.navigationItem.largeTitleDisplayMode = isRoot
        ? UINavigationItemLargeTitleDisplayModeAlways
        : UINavigationItemLargeTitleDisplayModeNever;
    if (isRoot) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                target:self action:@selector(closeTapped)];
        self.tableView.tableHeaderView = FBTGlassOverviewHeader(self.tableView.bounds.size.width);
    }
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
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
            @{ @"kind": @"switch", @"title": @"Toque duplo com três dedos", @"subtitle": @"Abre a FBTweak em qualquer tela. O ícone em Configurações continua disponível.", @"key": FBTKeyOpenThreeFingerDoubleTap },
        ],
        @[
            @{ @"kind": @"switch", @"title": @"Employee / Internal", @"subtitle": @"Getters conhecidos via Logos/MSHookMessageEx.", @"key": FBTKeyEmployeeEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Test User (local)", @"subtitle": @"Gates específicos de contas de teste; não concede permissões remotas.", @"key": FBTKeyTestUserEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Dogfood — gates conhecidos", @"subtitle": @"Ativa os hooks locais verificados, separado de Employee.", @"key": FBTKeyKnownDogfoodEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Aparelho gerenciado — preferência local", @"subtitle": @"Controla FBDogFood-managedPhoneFlag na IPA. NÃO comprova MDM ou Gold instalado.", @"key": @"FBDogFood-managedPhoneFlag" },
            @{ @"kind": @"switch", @"title": @"Internal React Native", @"subtitle": @"RCTDevMenu e dev settings da bridge ativa.", @"key": FBTKeyReactNativeInternalEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Simular build Beta (local)", @"subtitle": @"METAOSBuildIsBeta import; não altera distribuição do aplicativo.", @"key": FBTKeyBetaBuildEnabled, @"restart": @YES },
            @{ @"kind": @"switch", @"title": @"Mobile Lab (LAB_IS_ACTIVE)", @"subtitle": @"Ativado por padrao. Define a variavel no inicio do processo; exige encerrar totalmente e reiniciar o Facebook. Nao concede permissao Employee no servidor.", @"key": FBTKeyMobileLabEnabled, @"restart": @YES },
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
            @{ @"kind": @"switch", @"title": @"MobileConfig runtime", @"subtitle": @"Controla registros e fallback dos readers. Live e Aquecer também ativam a sessão; desligar pausa os readers, mantendo os hooks instalados.", @"key": FBTKeyMobileConfigRuntimeEnabled },
            @{ @"kind": @"switch", @"title": @"Aquecer MobileConfig nativo", @"subtitle": @"Prepara o UI nativo e o contexto de sessão; depende da classe carregada.", @"key": FBTKeyMobileConfigNativeUIWarmupEnabled },
            @{ @"kind": @"switch", @"title": @"Capturar leituras MobileConfig", @"subtitle": @"Registra chave, tipo, default, resultado e contador dos readers interceptados. Leituras com override continuam registradas quando desligado.", @"key": FBTKeyMobileConfigCaptureEnabled },
            @{ @"kind": @"switch", @"title": @"Log QE-info (seguro)", @"subtitle": @"Registra seleções e alertas QE da interface nativa, sem interceptação global. Ative antes dos probes nativos.", @"key": FBTKeyMobileConfigFetchDiagnosticsEnabled },
            @{ @"kind": @"switch", @"title": @"Probe Tigon nativo (sessão / experimental)", @"subtitle": @"Captura status e callback TigonSimpleCallbacks com slots+UUID verificados. Não intercepta NSURLSession ou __TEXT. Desativa ao reiniciar.", @"key": FBTMCNativeProbeTigonKey },
            @{ @"kind": @"switch", @"title": @"Probe fetch MobileConfig (sessão / experimental)", @"subtitle": @"Observa asyncFetch e callback original do FBMobileConfigTigonFetcher; nenhum parâmetro enviado é alterado. Desativa ao reiniciar.", @"key": FBTMCNativeProbeFetcherKey },
            @{ @"kind": @"switch", @"title": @"Aplicar overrides MobileConfig", @"subtitle": @"Tenta OverridesTable nativo quando há contexto vivo; mantém fallback por accessor fishhookado.", @"key": FBTKeyMobileConfigOverridesEnabled },
            @{ @"kind": @"switch", @"title": @"Runtime BOOL browser", @"subtitle": @"Busca main-exec/FBShared/RN/framework por classe, selector e imagem; salva Force ON/OFF.", @"key": FBTKeyRuntimeBoolBrowserEnabled },
        ],
        @[
            @{ @"kind": @"nav", @"title": @"MobileConfig local — todos os mapas", @"subtitle": @"Busca por nome/ID e edição de overrides sem depender de QE-info.", @"dest": @"localconfig" },
            @{ @"kind": @"nav", @"title": @"Network Inspector — 100% iPhone", @"subtitle": @"Request/response MobileConfig e QE-info, correlação Tigon, exportação de bytes e headers conhecidos. Sem proxy.", @"dest": @"networkinspector" },
            @{ @"kind": @"nav", @"title": @"Diagnóstico do download de nomes", @"subtitle": @"Capturar, ver o erro remoto e compartilhar pelo iPhone.", @"dest": @"namesdiagnostic" },
            @{ @"kind": @"nav", @"title": @"MobileConfig Live", @"subtitle": @"Monitor + override por uint64 capturado.", @"dest": @"mobileconfig" },
            @{ @"kind": @"nav", @"title": @"Runtime Browser", @"subtitle": @"Exec + FBShared + FBSharedDynamic + RN. Abas ObjC/C/DATA/Swift. Force ON/OFF.", @"dest": @"bool" },
            @{ @"kind": @"nav", @"title": @"ObjC BOOL Live", @"subtitle": @"Observar sem alterar retorno ou manter Force ON/OFF persistido.", @"dest": @"boollive" },
            @{ @"kind": @"nav", @"title": @"Native Live Trace", @"subtitle": @"Eventos BOOL + QE/Tigon, buffer em memória e exportação JSON; sem Frida.", @"dest": @"livetrace" },
            @{ @"kind": @"nav", @"title": @"Headline flags", @"subtitle": @"Flags filtradas: internal, dogfood, dating, debug.", @"dest": @"headline" },
            @{ @"kind": @"nav", @"title": @"Dump completo de flags", @"subtitle": @"FBTFlags.json empacotado.", @"dest": @"flags" },
            @{ @"kind": @"nav", @"title": @"Query configs enviados", @"subtitle": @"GraphQL IDs/variáveis empacotados no bundle.", @"dest": @"queries" },
        ],
        @[
            @{ @"kind": @"action", @"title": @"Abrir Internal Settings nativo", @"subtitle": @"Chama FBInternalSettingsViewControllerFromSession(session).", @"action": @"native" },
            @{ @"kind": @"action", @"title": @"Abrir Internal Settings RN", @"subtitle": @"Usa a rota React Native fb://rninternalsettings existente na IPA 567.", @"action": @"rn_internal" },
            @{ @"kind": @"action", @"title": @"Mostrar React Native Dev Menu", @"subtitle": @"Procura o RCTDevMenu da bridge ativa e chama o método nativo -show; não cria bridge nova.", @"action": @"rn_dev" },
            @{ @"kind": @"action", @"title": @"Dogfooding Assistant — buscar no nativo", @"subtitle": @"Abre Internal Settings e procura Dogfooding no catálogo nativo; disponível só se o provider existir.", @"action": @"dogfood_assistant" },
            @{ @"kind": @"action", @"title": @"FFDB — buscar plugin nativo", @"subtitle": @"Usa o buscador do menu nativo; depende do plugin FFDB registrado.", @"action": @"ffdb_internal" },
            @{ @"kind": @"action", @"title": @"MobileConfig Debug — buscar nativo", @"subtitle": @"Usa busca nativa preservando os context managers sessioned e sessionless.", @"action": @"mc_debug_native" },
            @{ @"kind": @"action", @"title": @"Employee Settings — buscar nativo", @"subtitle": @"Procura Employee no Internal Settings original, conforme plugins disponíveis.", @"action": @"employee_internal" },
            @{ @"kind": @"action", @"title": @"Aviso DogFood / Gold — painel nativo", @"subtitle": @"Abre o painel Swift com callback LOCAL. Não equivale à adesão Gold/MDM.", @"action": @"dogfood_nag" },
            @{ @"kind": @"action", @"title": @"DogFood / Gold — estado local", @"subtitle": @"Mostra managedPhoneFlag e o estado Employee; não afirma elegibilidade MDM ou Gold remoto.", @"action": @"gold_status" },
            @{ @"kind": @"action", @"title": @"Gold — página oficial de builds", @"subtitle": @"Abre fb.me/builds, endereço encontrado no fluxo de pré-produção da IPA 567.", @"action": @"gold_builds" },
            @{ @"kind": @"action", @"title": @"Diagnosticar superfícies internas", @"subtitle": @"Lista classes nativas RN, FFDB, Dogfooding Assistant, Gold e MobileConfig realmente carregadas.", @"action": @"native_surfaces_diag" },
            @{ @"kind": @"action", @"title": @"Abrir Whitehat nativo", @"subtitle": @"Abre a tela de diagnóstico de rede do aplicativo.", @"action": @"whitehat" },
            @{ @"kind": @"action", @"title": @"Criar mc_overrides.json nativo", @"subtitle": @"Usa o path nativo capturado por getOverridesTablePath; abre o menu nativo antes se aparecer unknown.", @"action": @"ensure_mc_file" },
            @{ @"kind": @"action", @"title": @"A/B QE-info: isolar refresh/hash", @"subtitle": @"Desliga uma flag suspeita por teste, registra o estado do arquivo e permite restaurar o estado anterior.", @"action": @"qe_ab" },
            @{ @"kind": @"action", @"title": @"Limpar overrides runtime", @"subtitle": @"Remove MobileConfig + ObjC BOOL overrides persistidos.", @"action": @"clear" },
        ],
    ];

    // Keep all existing controls/actions as the canonical catalog, but never
    // show the huge flat catalog on the root page. Reuse their existing action
    // dispatch in focused submenus so behavior cannot drift.
    NSArray<NSArray<NSDictionary *> *> *catalog = self.sections;
    NSArray<NSDictionary *> *(^keys)(NSArray<NSString *> *) = ^NSArray *(NSArray *v) {
        return FBTMenuRows(catalog, @"key", v);
    };
    NSArray<NSDictionary *> *(^actions)(NSArray<NSString *> *) = ^NSArray *(NSArray *v) {
        return FBTMenuRows(catalog, @"action", v);
    };
    NSArray<NSDictionary *> *(^destinations)(NSArray<NSString *> *) = ^NSArray *(NSArray *v) {
        return FBTMenuRows(catalog, @"dest", v);
    };

    if (!self.menuGroup.length) {
        self.sections = @[
            keys(@[FBTKeyMasterEnabled, FBTKeyOpenThreeFingerDoubleTap]),
            @[
                @{@"kind": @"submenu", @"title": @"Employee e Internal", @"subtitle": @"Identidade local, Test User e menus internos", @"group": @"employee", @"symbol": @"person.crop.circle.badge.checkmark"},
                @{@"kind": @"submenu", @"title": @"Dogfood e Gold", @"subtitle": @"Nag nativo, managedPhoneFlag, builds e Assistant", @"group": @"dogfood", @"symbol": @"pawprint"},
                @{@"kind": @"submenu", @"title": @"React Native", @"subtitle": @"Internal Settings RN e Developer Menu", @"group": @"react", @"symbol": @"square.stack.3d.up"},
                @{@"kind": @"submenu", @"title": @"MobileConfig e QE", @"subtitle": @"Sessioned, sessionless, overrides e nomes", @"group": @"mobileconfig", @"symbol": @"slider.horizontal.3"},
                @{@"kind": @"submenu", @"title": @"Diagnóstico e ferramentas", @"subtitle": @"Rede, trace, browsers e símbolos", @"group": @"diagnostics", @"symbol": @"waveform.path.ecg"},
                @{@"kind": @"submenu", @"title": @"Aparência e recursos", @"subtitle": @"Liquid Glass, tab bar, Dating e build Beta", @"group": @"appearance", @"symbol": @"circle.hexagongrid"}
            ],
            actions(@[@"native", @"dogfood_nag", @"rn_internal"])
        ];
        self.sectionTitles = @[@"Geral", @"Áreas", @"Acesso rápido"];
        return;
    }

    NSArray *toggles = @[];
    NSArray *native = @[];
    NSArray *tools = @[];
    if ([self.menuGroup isEqualToString:@"employee"]) {
        toggles = keys(@[FBTKeyEmployeeEnabled, FBTKeyTestUserEnabled,
                         FBTKeyMobileLabEnabled, FBTKeyInternalCImportsEnabled,
                         FBTKeyEasyGatingInternalEnabled, FBTKeyInternalDebugSweepEnabled]);
        native = actions(@[@"native", @"employee_internal", @"whitehat", @"ffdb_internal"]);
        tools = actions(@[@"native_surfaces_diag"]);
    } else if ([self.menuGroup isEqualToString:@"dogfood"]) {
        toggles = keys(@[@"FBDogFood-managedPhoneFlag", FBTKeyKnownDogfoodEnabled,
                         FBTKeyDogfoodSweepEnabled]);
        native = actions(@[@"dogfood_nag", @"dogfood_assistant", @"gold_builds"]);
        tools = actions(@[@"gold_status", @"native_surfaces_diag"]);
    } else if ([self.menuGroup isEqualToString:@"react"]) {
        toggles = keys(@[FBTKeyReactNativeInternalEnabled]);
        native = actions(@[@"rn_internal", @"rn_dev"]);
        tools = actions(@[@"native_surfaces_diag"]);
    } else if ([self.menuGroup isEqualToString:@"mobileconfig"]) {
        toggles = keys(@[FBTKeyMobileConfigRuntimeEnabled, FBTKeyMobileConfigNativeUIWarmupEnabled, FBTKeyMobileConfigCaptureEnabled,
                         FBTKeyMobileConfigOverridesEnabled, FBTKeyMobileConfigFetchDiagnosticsEnabled,
                         FBTMCNativeProbeTigonKey, FBTMCNativeProbeFetcherKey]);
        native = actions(@[@"mc_debug_native", @"ensure_mc_file", @"qe_ab"]);
        tools = destinations(@[@"localconfig", @"namesdiagnostic", @"mobileconfig"]);
    } else if ([self.menuGroup isEqualToString:@"diagnostics"]) {
        toggles = keys(@[FBTKeyRuntimeBoolBrowserEnabled]);
        native = destinations(@[@"networkinspector", @"bool", @"boollive",
                                @"livetrace", @"headline", @"flags", @"queries"]);
        tools = actions(@[@"native_surfaces_diag", @"clear"]);
    } else if ([self.menuGroup isEqualToString:@"appearance"]) {
        toggles = keys(@[FBTKeyLiquidGlassEnabled, FBTKeyFloatingTabBarEnabled,
                         FBTKeyDatingEnabled, FBTKeyBetaBuildEnabled]);
        native = destinations(@[@"feat:LiquidGlass", @"feat:FloatingTab", @"feat:DatingGemstone"]);
    }

    NSMutableArray *grouped = [NSMutableArray array];
    NSMutableArray *headers = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; ++i) {
        NSArray *rows = i == 0 ? toggles : (i == 1 ? native : tools);
        if (!rows.count) continue;
        [grouped addObject:rows];
        [headers addObject:i == 0 ? @"Controles" : (i == 1 ? @"Menus e recursos" : @"Ferramentas")];
    }
    self.sections = grouped;
    self.sectionTitles = headers;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section >= 0 && (NSUInteger)section < self.sectionTitles.count)
        return self.sectionTitles[(NSUInteger)section];
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
    if (self.menuGroup.length) {
        if ([self.menuGroup isEqualToString:@"dogfood"] && section == 0)
            return @"managedPhoneFlag é uma preferência local — não autentica Employee nem inscreve em MDM. O painel Gold usa callbacks fornecidos pelo chamador.";
        if ([self.menuGroup isEqualToString:@"employee"] && section == 0)
            return @"Os gates locais permitem interfaces, mas cada plugin ainda pode exigir sessão, provider e autorização remota.";
        return nil;
    }
    if (section == 2) return @"Ativar a instrumentação ou o log não confirma que o fetch funcionou. Confira os hooks disponíveis, leituras observadas e respostas no diagnóstico.";
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
        sw.on = FBTMCNativeProbeIsKey(sw.prefKey) ?
            FBTMCNativeProbeIsEnabled(sw.prefKey) :
            [[NSUserDefaults standardUserDefaults] boolForKey:sw.prefKey];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([kind isEqualToString:@"nav"] ||
               [kind isEqualToString:@"submenu"] ||
               [kind isEqualToString:@"action"]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    NSString *symbol = item[@"symbol"];
    if (symbol.length) {
        UIImage *image = [UIImage systemImageNamed:symbol];
        if (image) {
            cfg.image = image;
            cfg.imageProperties.tintColor = [UIColor secondaryLabelColor];
            cell.contentConfiguration = cfg;
        }
    }
    NSString *identifier = item[@"group"] ?: item[@"action"] ?: item[@"dest"] ?: item[@"key"];
    if (identifier.length) cell.accessibilityIdentifier =
        [@"fbt.settings." stringByAppendingString:identifier];
    return cell;
}

- (void)showInfoTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)switchChanged:(FBTSettingsSwitch *)sender {
    if ([sender.prefKey isEqualToString:@"FBDogFood-managedPhoneFlag"]) {
        FBTDogFoodSetManagedPhoneFlag(sender.isOn);
        sender.on = FBTDogFoodManagedPhoneFlag();
        [self.tableView reloadData];
        return;
    }
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
    FBTSettingsGateDidSwitch(sender.prefKey, sender.isOn);
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
    if ([kind isEqualToString:@"submenu"]) {
        FBTSettingsViewController *controller = [[FBTSettingsViewController alloc]
            initWithStyle:UITableViewStyleInsetGrouped];
        controller.menuGroup = item[@"group"];
        controller.title = item[@"title"];
        [self.navigationController pushViewController:controller animated:YES];
        return;
    }
    if ([kind isEqualToString:@"nav"]) {
        NSString *dest = item[@"dest"];
        UIViewController *vc = nil;
        if ([dest isEqualToString:@"localconfig"]) vc = [[FBTLocalConfigViewController alloc] initWithSearchQuery:@""];
        else if ([dest isEqualToString:@"namesdiagnostic"]) vc = [[FBTNamesDiagnosticsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"networkinspector"]) vc = [[FBTNetworkInspectorViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"mobileconfig"]) vc = [[FBTMobileConfigViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        else if ([dest isEqualToString:@"bool"]) vc = [[FBTSymbolsBrowserViewController alloc] initWithMode:FBTCSymbolsBrowserModeObjCMethods];
        else if ([dest isEqualToString:@"boollive"]) vc = [[FBTRuntimeBoolViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
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
        } else if ([action isEqualToString:@"rn_internal"]) {
            [self dismissViewControllerAnimated:YES completion:^{
                FBTOpenReactNativeInternalSettings();
            }];
        } else if ([action isEqualToString:@"rn_dev"]) {
            [self dismissViewControllerAnimated:YES completion:^{
                NSString *failure = nil;
                if (!FBTNativeShowReactDevMenu([FBTUtils topMostController], &failure)) {
                    [FBTUtils showMessage:failure ?: @"RCTDevMenu indisponível na sessão atual."
                                   title:@"React Native Dev Menu"];
                }
            }];
        } else if ([action isEqualToString:@"dogfood_assistant"] ||
                   [action isEqualToString:@"ffdb_internal"] ||
                   [action isEqualToString:@"mc_debug_native"] ||
                   [action isEqualToString:@"employee_internal"]) {
            // Open the real Internal Settings controller with its original
            // session and ask its own search provider for the requested plugin.
            // No guessed initWithSession: or unverified plugin constructor.
            NSDictionary *nativeTerms = @{
                @"dogfood_assistant": @"Dogfooding",
                @"ffdb_internal": @"FFDB",
                @"mc_debug_native": @"MobileConfig",
                @"employee_internal": @"Employee"
            };
            NSString *query = nativeTerms[action];
            [self dismissViewControllerAnimated:YES completion:^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"FBTRequestOpenNativeInternalSettings"
                                object:nil
                              userInfo:@{@"pluginSearch": query ?: @""}];
            }];
        } else if ([action isEqualToString:@"gold_status"]) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSString *status = [NSString stringWithFormat:
                @"managedPhoneFlag: %@\nEmployee / Internal: %@\nSnooze switch: %@\nSnooze dismiss: %@\n\nOs valores são locais. Não comprovam MDM, Gold instalado ou autorização remota.",
                [defaults boolForKey:@"FBDogFood-managedPhoneFlag"] ? @"YES" : @"NO",
                [FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ? @"ON" : @"OFF",
                [defaults objectForKey:@"FBDogFood-lastSnoozedOnSwitchDate"] ?: @"não definido",
                [defaults objectForKey:@"FBDogFood-lastSnoozedOnDismissDate"] ?: @"não definido"];
            [self showInfoTitle:@"DogFood / Gold" message:status];
        } else if ([action isEqualToString:@"gold_builds"]) {
            NSURL *url = [NSURL URLWithString:@"https://fb.me/builds"];
            [[UIApplication sharedApplication] openURL:url options:@{}
                completionHandler:^(BOOL success) {
                    if (!success) [FBTUtils showMessage:@"Não foi possível abrir a página de builds."
                                                  title:@"Gold / builds"];
                }];
        } else if ([action isEqualToString:@"native_surfaces_diag"]) {
            NSString *report = FBTNativeInternalSurfacesReport();
            UIAlertController *info = [UIAlertController
                alertControllerWithTitle:@"Diagnóstico de menus nativos"
                message:report preferredStyle:UIAlertControllerStyleAlert];
            [info addAction:[UIAlertAction actionWithTitle:@"Copiar"
                   style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *choice) {
                       UIPasteboard.generalPasteboard.string = report;
                   }]];
            [info addAction:[UIAlertAction actionWithTitle:@"Fechar"
                   style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:info animated:YES completion:nil];
        } else if ([action isEqualToString:@"dogfood_nag"]) {
            NSString *reason = nil;
            if (!FBTDogFoodPresentNativeNag(self, &reason)) {
                [self showInfoTitle:@"DogFood / Gold nativo" message:reason ?: @"Interface nativa indisponível."];
            }
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
    self.title = @"ObjC BOOL Runtime";
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

- (void)showNativeTrace {
    [self.navigationController pushViewController:[[FBTNativeTraceViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
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
    NSString *force = [e[@"forced"] boolValue] ? [NSString stringWithFormat:@" · FORCE %@", FBTBoolText([e[@"force"] boolValue])] : ([e[@"observing"] boolValue] ? @" · OBSERVE" : @"");
    NSString *hookState = e[@"installState"] ?: @"unknown";
    id original = e[@"observedOriginal"];
    id effective = e[@"observedEffective"];
    NSString *originalLabel = original && original != [NSNull null] ? FBTBoolText([original boolValue]) : @"?";
    NSString *effectiveLabel = effective && effective != [NSNull null] ? FBTBoolText([effective boolValue]) : @"?";
    cfg.secondaryText = [NSString stringWithFormat:@"%@ · %@%@\nHook: %@ · Original: %@ · Efetivo: %@ · Chamadas: %@",
                         e[@"class"] ?: @"", e[@"imageKind"] ?: @"unknown", force, hookState,
                         originalLabel, effectiveLabel, e[@"invocationCount"] ?: @0];
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
    [a addAction:[UIAlertAction actionWithTitle:@"Observar (sem forçar)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { FBTRuntimeBoolObserve(e); [self runSearch]; }]];
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

