#import "FBTFeatureParamsViewController.h"
#import "FBTFeatureCatalog.h"
#import "FBTLocalConfigViewController.h"
#import "FBTBrowserCompat.h"
#import "../FBTUtils.h"
#import "../Runtime/FBTLocalConfigCatalog.h"
#import "../Runtime/FBTMCOverridesFile.h"
#import "../Runtime/FBTNativeMobileConfigOverrides.h"
#import <objc/runtime.h>

static const void *kCfg = &kCfg, *kIdx = &kIdx, *kName = &kName;

@implementation FBTFeatureParamsViewController {
    NSString *_featureId;
    NSArray<NSDictionary *> *_localConfigurations;
    BOOL _loadingLocalConfigurations;
    BOOL _loadedLocalConfigurations;
}

- (instancetype)initWithFeatureId:(NSString *)featureId {
    NSDictionary *feat = nil;
    for (NSDictionary *f in [FBTFeatureCatalog features]) if ([f[@"id"] isEqualToString:featureId]) { feat = f; break; }
    self = [super initWithTitle:feat[@"title"] ?: featureId];
    if (self) { _featureId = featureId; [self rebuild]; }
    return self;
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self rebuild]; }

- (void)loadLocalConfigurations {
    if (_loadingLocalConfigurations || _loadedLocalConfigurations) return;
    _loadingLocalConfigurations = YES;
    NSString *featureId = [_featureId copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *configurations = [FBTFeatureCatalog configurationsForFeatureId:featureId
            localConfigurations:[FBTLocalConfigCatalog configurations]];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_localConfigurations = configurations;
            self->_loadingLocalConfigurations = NO;
            self->_loadedLocalConfigurations = YES;
            [self rebuild];
        });
    });
}

- (NSString *)parameterSummaryForConfiguration:(NSDictionary *)configuration {
    NSArray *parameters = configuration[@"params"];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSArray *types = @[@"bool", @"int64", @"string", @"double"];
    NSUInteger unknown = 0;
    for (NSDictionary *parameter in parameters) {
        NSString *type = parameter[@"type"];
        if (![types containsObject:type ?: @""]) { ++unknown; continue; }
        counts[type] = @([counts[type] unsignedIntegerValue] + 1);
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *type in types) {
        if ([counts[type] unsignedIntegerValue])
            [parts addObject:[NSString stringWithFormat:@"%@ %@", type, counts[type]]];
    }
    if (unknown) [parts addObject:[NSString stringWithFormat:@"%lu sem tipo reconhecido", (unsigned long)unknown]];
    NSString *total = [NSString stringWithFormat:@"%lu parâmetros", (unsigned long)parameters.count];
    return parts.count ? [NSString stringWithFormat:@"%@ · %@", total, [parts componentsJoinedByString:@" · "]] : total;
}

- (void)rebuildLocalConfigurations {
    NSMutableArray<FBTBaseSettingsRow *> *rows = [NSMutableArray array];
    if (!_loadedLocalConfigurations) {
        [rows addObject:[FBTBaseSettingsRow rowWithTitle:@"Lendo configurações locais…" subtitle:nil action:nil]];
    } else {
        for (NSDictionary *configuration in _localConfigurations) {
            NSString *name = configuration[@"name"];
            NSString *title = name.length ? [NSString stringWithFormat:@"%@: %@", configuration[@"id"], name]
                : [configuration[@"id"] description];
            NSString *subtitle = [NSString stringWithFormat:@"%@\n%@ · %@", [self parameterSummaryForConfiguration:configuration],
                configuration[@"scope"] ?: @"Escopo não informado", configuration[@"source"] ?: @"Mapa não informado"];
            FBTBaseSettingsRow *row = [FBTBaseSettingsRow rowWithTitle:title subtitle:subtitle action:^(UIViewController *vc) {
                FBTLocalConfigViewController *editor = [[FBTLocalConfigViewController alloc] initWithConfiguration:configuration];
                [vc.navigationController pushViewController:editor animated:YES];
            }];
            row.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            [rows addObject:row];
        }
        if (!rows.count) [rows addObject:[FBTBaseSettingsRow rowWithTitle:@"Nenhuma configuração encontrada"
            subtitle:@"Estes IDs não aparecem nos mapas locais disponíveis." action:nil]];
    }
    self.sections = @[[FBTBaseSettingsSection sectionWithHeader:@"Configurações locais"
        footer:@"Cada linha preserva seu mapa e escopo. Abra para consultar todos os parâmetros e editar valores por tipo."
        rows:rows]];
    [self reloadSettings];
    if (!_loadedLocalConfigurations) [self loadLocalConfigurations];
}

- (UISegmentedControl *)segForConfig:(NSString *)cfg idx:(NSInteger)idx name:(NSString *)name {
    UISegmentedControl *s = [[UISegmentedControl alloc] initWithItems:@[@"SYS", @"OFF", @"ON"]];
    s.selectedSegmentIndex = (NSInteger)[FBTMCOverridesFile stateForConfig:cfg paramIdx:idx];
    s.apportionsSegmentWidthsByContent = YES;
    objc_setAssociatedObject(s, kCfg, cfg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(s, kIdx, @(idx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(s, kName, name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [s addTarget:self action:@selector(segChanged:) forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)segChanged:(UISegmentedControl *)s {
    NSString *cfg = objc_getAssociatedObject(s, kCfg);
    NSInteger idx = [objc_getAssociatedObject(s, kIdx) integerValue];
    NSString *name = objc_getAssociatedObject(s, kName);
    FBTMCState requested = (FBTMCState)s.selectedSegmentIndex;
    NSError *error = nil;
    BOOL saved = [FBTMCOverridesFile setState:requested forConfig:cfg paramIdx:idx name:name error:&error];
    FBTMCState persisted = [FBTMCOverridesFile stateForConfig:cfg paramIdx:idx];
    s.selectedSegmentIndex = (NSInteger)persisted;
    if (!saved) {
        [FBTUtils showToastForDuration:2.8 title:@"Alteração não gravada" subtitle:error.localizedDescription ?: @"Não foi possível gravar o arquivo de overrides."];
        return;
    }
    if (persisted != requested) {
        [FBTUtils showToastForDuration:2.8 title:@"Gravação não confirmada" subtitle:@"O estado relido do arquivo difere da seleção. Atualize e tente novamente."];
        return;
    }
    [FBTUtils showToastForDuration:1.3 title:@"Override salvo no mc_overrides.json" subtitle:@"Arquivo conferido; reabra o Facebook para recarregar."];
}

- (void)rebuild {
    NSDictionary *feat = nil;
    for (NSDictionary *f in [FBTFeatureCatalog features]) if ([f[@"id"] isEqualToString:_featureId]) { feat = f; break; }
    if ([feat[@"configurationIDs"] isKindOfClass:NSArray.class]) {
        [self rebuildLocalConfigurations];
        return;
    }
    NSMutableArray<FBTBaseSettingsSection *> *sections = [NSMutableArray array];

    if (![FBTMCOverridesFile fileExists]) {
        FBTBaseSettingsRow *warn = [FBTBaseSettingsRow rowWithTitle:@"Criar mc_overrides.json"
            subtitle:@"O arquivo nativo ainda não existe. Toque p/ criar (ou abra Internal Settings nativo uma vez)."
            action:^(UIViewController *vc) {
                FBTNativeMobileConfigEnsureOverridesFile();
                [(FBTFeatureParamsViewController *)vc rebuild];
            }];
        warn.titleColor = [UIColor systemOrangeColor];
        [sections addObject:[FBTBaseSettingsSection sectionWithHeader:@"Estado" footer:
            @"SYS = sem override (padrão do app). OFF/ON = força no MobileConfig nativo." rows:@[warn]]];
    }

    for (NSDictionary *cfg in feat[@"configs"]) {
        NSString *ck = cfg[@"config"];
        NSArray *params = cfg[@"params"];
        if (![params isKindOfClass:NSArray.class] || params.count == 0) continue;
        NSMutableArray<FBTBaseSettingsRow *> *rows = [NSMutableArray array];
        for (NSDictionary *p in params) {
            NSInteger idx = [p[@"idx"] integerValue];
            NSString *name = p[@"name"];
            FBTBaseSettingsRow *row = [FBTBaseSettingsRow rowWithTitle:name
                subtitle:[NSString stringWithFormat:@"idx %ld", (long)idx] action:nil];
            __weak typeof(self) ws = self;
            row.accessoryProvider = ^UIView *{ return [ws segForConfig:ck idx:idx name:name]; };
            [rows addObject:row];
        }
        [sections addObject:[FBTBaseSettingsSection sectionWithHeader:ck footer:nil rows:rows]];
    }
    self.sections = sections;
    [self reloadSettings];
}
@end
