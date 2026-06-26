#import "FBTFeatureParamsViewController.h"
#import "FBTFeatureCatalog.h"
#import "FBTBrowserCompat.h"
#import "../FBTUtils.h"
#import "../Runtime/FBTMCOverridesFile.h"
#import "../Runtime/FBTNativeMobileConfigOverrides.h"
#import <objc/runtime.h>

static const void *kCfg = &kCfg, *kIdx = &kIdx, *kName = &kName;

@implementation FBTFeatureParamsViewController { NSString *_featureId; }

- (instancetype)initWithFeatureId:(NSString *)featureId {
    NSDictionary *feat = nil;
    for (NSDictionary *f in [FBTFeatureCatalog features]) if ([f[@"id"] isEqualToString:featureId]) { feat = f; break; }
    self = [super initWithTitle:feat[@"title"] ?: featureId];
    if (self) { _featureId = featureId; [self rebuild]; }
    return self;
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self rebuild]; }

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
    [FBTMCOverridesFile setState:(FBTMCState)s.selectedSegmentIndex forConfig:cfg paramIdx:idx name:name];
    [FBTUtils showToastForDuration:1.3 title:@"Override salvo no mc_overrides.json" subtitle:@"Aplica no próximo launch do Facebook"];
}

- (void)rebuild {
    NSDictionary *feat = nil;
    for (NSDictionary *f in [FBTFeatureCatalog features]) if ([f[@"id"] isEqualToString:_featureId]) { feat = f; break; }
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
