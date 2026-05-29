#import "FBGRSurfaceListVC.h"
#import "FBGRMenuTheme.h"
#import "FBGRGateCategoryVC.h"
#import "FBGRGateRuntimeBrowserVC.h"
#import "FBGRLogViewController.h"
#import "../Runtime/FBGRGateRegistry.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../FBGramPrefix.h"

extern BOOL      FBGRLiquidGlassIsHooked(void);
extern void      FBGRMCGateHooksEnsureInstalled(void);
extern void      FBGRMCGateCacheRefresh(void);
extern NSString *FBGRMCGateHooksDiagnostic(void);
extern NSString *FBGRMCNativeHooksDiagnostic(void);
extern void      FBGRMCObserverFlush(void);
extern NSUInteger FBGRMCObserverSlotCount(void);
extern NSString *FBGRMCObserverDump(void);
extern BOOL      FBGRDogFoodIsEnabled(void);
extern void      FBGRDogFoodSetEnabled(BOOL);
extern BOOL      FBGRDogFoodPresentNagSheet(void);
extern NSString *FBGRDogFoodDiagnostic(void);

typedef NS_ENUM(NSInteger, FBGRRootSection) {
    FBGRRootSectionProviders = 0,
    FBGRRootSectionAllParams = 1,
    FBGRRootSectionDogFood   = 2,
    FBGRRootSectionObserver  = 3,
    FBGRRootSectionDiag      = 4,
    FBGRRootSectionCount     = 5,
};

static UIViewController *FBGRTopVC(void) {
    UIViewController *c = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w.isKeyWindow) { c = w.rootViewController; break; }
        if (c) break;
    }
    while (c) {
        if (c.presentedViewController) { c = c.presentedViewController; continue; }
        if ([c isKindOfClass:UINavigationController.class]) { UIViewController *v = ((UINavigationController*)c).visibleViewController; if (v && v!=c){c=v;continue;} }
        if ([c isKindOfClass:UITabBarController.class]) { UIViewController *v = ((UITabBarController*)c).selectedViewController; if (v && v!=c){c=v;continue;} }
        break;
    }
    return c;
}

void FBGRPresentMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = FBGRTopVC();
        if (!top) return;
        if ([top isKindOfClass:FBGRSurfaceListVC.class]) return;
        if ([top.navigationController.topViewController isKindOfClass:FBGRSurfaceListVC.class]) return;
        FBGRSurfaceListVC *menu = [[FBGRSurfaceListVC alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:menu];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        if (@available(iOS 15.0, *)) {
            nav.sheetPresentationController.prefersGrabberVisible = YES;
            nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
        }
        [top presentViewController:nav animated:YES completion:nil];
    });
}

@interface FBGRSurfaceListVC ()
@property(nonatomic, strong) NSArray<FBGRGateProvider *> *providers;
@end

@implementation FBGRSurfaceListVC

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FBTweaks";
    _providers = [FBGRGateRegistry allProviders];
    FBGRApplyTable(self.tableView, self);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(doClose)];
    [[FBGRMCCatalog shared] loadIfNeeded];
    FBGRMCGateHooksEnsureInstalled();
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)doClose { [self dismissViewControllerAnimated:YES completion:nil]; }

// ── TableView ─────────────────────────────────────────────────────────────────
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return FBGRRootSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case FBGRRootSectionProviders: return (NSInteger)_providers.count;
        case FBGRRootSectionAllParams: return 1;
        case FBGRRootSectionDogFood:   return 2; // nag flow + diag
        case FBGRRootSectionObserver:  return 2; // toggle + flush
        case FBGRRootSectionDiag:      return 4; // hooks diag + log + restart + reset all
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return (@[@"Categorias", @"Catálogo Completo", @"DogFood / Internal", @"MC Observer", @"Diagnóstico / Tools"])[(NSUInteger)s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == FBGRRootSectionProviders) {
        NSUInteger tot = FBGRGateAllOverrideSlotIds().count;
        NSUInteger cat = [FBGRMCCatalog shared].totalCount;
        return [NSString stringWithFormat:@"%lu overrides ativos  |  %lu params no catálogo  |  LG hook=%@",
                (unsigned long)tot, (unsigned long)cat,
                FBGRLiquidGlassIsHooked() ? @"OK" : @"MISS"];
    }
    if (s == FBGRRootSectionAllParams)
        return @"Todos os 5374 params do ReactMobileConfigMetadata. Toggle = override persistente.";
    if (s == FBGRRootSectionDogFood)
        return @"O nag nativo só marca o device como \"managed phone\" (Gold app). NÃO ativa "
               @"is_employee/internal sozinho — para isso use a categoria Employee/Dogfood acima.";
    if (s == FBGRRootSectionObserver)
        return @"Observer loga slotIds observados em runtime → mc_props_dump.json. "
               @"Ativar por alguns minutos e fazer flush gera o catálogo ao vivo do app.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"root"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"root"];
    FBGRApplyCell(c, ip.row + ip.section * 10, nil);
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (ip.section == FBGRRootSectionProviders) {
        FBGRGateProvider *p = _providers[(NSUInteger)ip.row];
        NSUInteger set = 0;
        for (NSNumber *sid in FBGRGateAllOverrideSlotIds()) {
            uint64_t s = [sid unsignedLongLongValue];
            for (FBGRFeaturedFlag *f in p.featured) if (f.slotId == s) { set++; break; }
        }
        c.imageView.image = FBGRSymbol(p.icon, FBGRAccentForProvider(p.accentColor));
        c.textLabel.text  = p.title;
        c.detailTextLabel.text = set > 0
            ? [NSString stringWithFormat:@"%lu override(s) ativo(s)", (unsigned long)set]
            : [NSString stringWithFormat:@"%lu featured flags", (unsigned long)p.featured.count];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }

    if (ip.section == FBGRRootSectionAllParams) {
        c.imageView.image = FBGRSymbol(@"list.bullet.rectangle", UIColor.systemTealColor);
        c.textLabel.text  = @"Todos os Params — Runtime Browser";
        c.detailTextLabel.text = [NSString stringWithFormat:@"%lu params  |  busca + toggle",
            (unsigned long)[FBGRMCCatalog shared].totalCount];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }

    if (ip.section == FBGRRootSectionObserver) {
        if (ip.row == 0) {
            c.textLabel.text = @"MC Observer";
            c.detailTextLabel.text = [NSString stringWithFormat:@"%lu slotIds capturados",
                (unsigned long)FBGRMCObserverSlotCount()];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = FBGRPref(kFBGRMCObserverEnabled);
            sw.onTintColor = UIColor.systemOrangeColor;
            [sw addTarget:self action:@selector(observerToggled:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
        } else {
            c.imageView.image = FBGRSymbol(@"arrow.down.doc", UIColor.systemOrangeColor);
            c.textLabel.text  = @"Flush para disco agora";
            c.detailTextLabel.text = @"/var/mobile/Library/.../FBTweaks/mc_props_dump.json";
        }
        return c;
    }

    if (ip.section == FBGRRootSectionDogFood) {
        if (ip.row == 0) {
            c.imageView.image = FBGRSymbol(@"ladybug.fill", UIColor.systemOrangeColor);
            c.textLabel.text  = @"Abrir nag nativo DogFood/Gold";
            c.detailTextLabel.text = @"Fluxo nativo de managed phone (não desbloqueia interno)";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            c.imageView.image = FBGRSymbol(@"stethoscope", UIColor.systemTealColor);
            c.textLabel.text  = @"DogFood / DLP Diagnóstico";
            c.detailTextLabel.text = @"Estado do controller, sessão e hook DLP";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return c;
    }

    // Diag
    if (ip.row == 0) {
        c.imageView.image = FBGRSymbol(@"wrench.and.screwdriver", UIColor.systemGreenColor);
        c.textLabel.text  = @"Hooks Diagnóstico";
        c.detailTextLabel.text = @"Ver estado dos hooks instalados";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.row == 1) {
        c.imageView.image = FBGRSymbol(@"doc.text", UIColor.systemCyanColor);
        c.textLabel.text  = @"Log em tempo real";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.row == 2) {
        c.imageView.image = FBGRSymbol(@"arrow.clockwise.circle.fill", UIColor.systemYellowColor);
        c.textLabel.text  = @"Aplicar e reiniciar Facebook";
        c.detailTextLabel.text = @"Necessário p/ gates lidos só no startup";
    } else {
        c.textLabel.text = @"Resetar TODOS os overrides";
        c.textLabel.textColor = UIColor.systemRedColor;
        c.imageView.image = FBGRSymbol(@"trash.fill", UIColor.systemRedColor);
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == FBGRRootSectionProviders) {
        FBGRGateProvider *p = _providers[(NSUInteger)ip.row];
        [self.navigationController pushViewController:
            [[FBGRGateCategoryVC alloc] initWithProvider:p] animated:YES];
        return;
    }
    if (ip.section == FBGRRootSectionAllParams) {
        [self.navigationController pushViewController:
            [[FBGRGateRuntimeBrowserVC alloc] initWithProvider:nil] animated:YES];
        return;
    }
    if (ip.section == FBGRRootSectionObserver && ip.row == 1) {
        FBGRMCObserverFlush();
        UITableViewCell *c = [tv cellForRowAtIndexPath:ip];
        c.detailTextLabel.text = @"Flushed ✓";
        return;
    }
    if (ip.section == FBGRRootSectionDogFood) {
        if (ip.row == 0) {
            BOOL ok = FBGRDogFoodPresentNagSheet();
            if (!ok) {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"DogFood"
                    message:@"Não foi possível abrir o nag nativo (controller ou sessão indisponível)."
                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            }
        } else {
            NSString *diag = FBGRDogFoodDiagnostic();
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"DogFood / DLP"
                message:diag preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Copiar" style:UIAlertActionStyleDefault handler:^(id _){
                [UIPasteboard generalPasteboard].string = diag;
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
        return;
    }
        if (ip.section == FBGRRootSectionDiag) {
        if (ip.row == 0) {
            NSString *diag = [NSString stringWithFormat:@"%@\n\n%@",
                FBGRMCGateHooksDiagnostic(), FBGRMCNativeHooksDiagnostic()];
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Hooks Diag"
                message:diag preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Copiar" style:UIAlertActionStyleDefault handler:^(id _){
                [UIPasteboard generalPasteboard].string = diag;
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        } else if (ip.row == 1) {
            [self.navigationController pushViewController:[FBGRLogViewController new] animated:YES];
        } else if (ip.row == 2) {
            UIAlertController *a = [UIAlertController
                alertControllerWithTitle:@"Reiniciar Facebook?"
                message:@"Toggles de MC que são lidos só no startup precisam de restart para aplicar."
                preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Reiniciar" style:UIAlertActionStyleDestructive handler:^(id _){
                FBGRMCGateCacheRefresh();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ exit(0); });
            }]];
            [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        } else {
            FBGRGateClearAll();
            FBGRMCGateCacheRefresh();
            [tv reloadData];
        }
    }
}

- (void)observerToggled:(UISwitch *)sw {
    [FBGRPrefs() setBool:sw.isOn forKey:kFBGRMCObserverEnabled];
    [FBGRPrefs() synchronize];
}

@end
