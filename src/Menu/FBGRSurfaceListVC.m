#import "FBGRSurfaceListVC.h"
#import "FBGRMenuTheme.h"
#import "FBGRGateCategoryVC.h"
#import "FBGRGateRuntimeBrowserVC.h"
#import "FBGRBoolRuntimeBrowserVC.h"
#import "FBGRLogViewController.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRLog.h"
#import "../Runtime/FBGRBoolRuntimeInventory.h"
extern "C" void FBGRMCGateHooksApplyPersistedOverrides(void);

extern void FBGRMCGateHooksEnsureInstalled(void);
extern NSString *FBGRMCGateHooksDiagnostic(void);
extern void FBGRLiquidGlassSetForced(BOOL forced);
extern NSString *FBGRLiquidGlassDiagnostic(void);
extern void FBGRDogFoodSetEnabled(BOOL enabled);
extern NSString *FBGRDogFoodDiagnostic(void);

static NSArray<NSNumber *> *FBGRCategories(void) {
    return @[
        @(FBGRFeatureCategoryUI), @(FBGRFeatureCategoryLiquidGlass), @(FBGRFeatureCategoryTabBar),
        @(FBGRFeatureCategoryDating), @(FBGRFeatureCategoryExperiments), @(FBGRFeatureCategoryDogfood),
        @(FBGRFeatureCategoryInternal), @(FBGRFeatureCategoryDebug), @(FBGRFeatureCategoryMarketplace),
        @(FBGRFeatureCategoryAI)
    ];
}

@implementation FBGRSurfaceListVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FBTweaks";
    FBGRApplyGlassController(self);
    FBGRApplyGlassTable(self.tableView);
    [[FBGRMCCatalog shared] loadIfNeeded];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Logs" style:UIBarButtonItemStylePlain target:self action:@selector(logs)];
}

- (void)logs { [self.navigationController pushViewController:[FBGRLogViewController new] animated:YES]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return (NSInteger)FBGRCategories().count;
    if (section == 1) return 3;
    return 5;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Feature map" : section == 1 ? @"Runtimes patcháveis" : @"Hooks / presets";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"root"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"root"];

    if (ip.section == 0) {
        FBGRFeatureCategory cat = (FBGRFeatureCategory)[FBGRCategories()[(NSUInteger)ip.row] integerValue];
        NSString *subtitle = [NSString stringWithFormat:@"%lu flags", (unsigned long)[[FBGRMCCatalog shared] paramsForCategory:cat].count];
        FBGRConfigureCell(c, FBGRFeatureCategoryTitle(cat), subtitle, FBGRSymbol(FBGRFeatureCategoryIcon(cat), FBGRAccentColor()));
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }

    if (ip.section == 1) {
        NSArray *titles = @[@"MobileConfig Runtime Browser", @"Executable Bool Runtime — Facebook", @"FBSharedFramework Bool Runtime"];
        NSArray *subs = @[@"toggle por slotId", @"Facebook executable", @"FBSharedFramework"];
        FBGRConfigureCell(c, titles[(NSUInteger)ip.row], subs[(NSUInteger)ip.row], FBGRSymbol(ip.row == 0 ? @"slider.horizontal.3" : @"cpu", FBGRAccentColor()));
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }

    NSArray *titles = @[@"Instalar/Recarregar hooks MobileConfig", @"Aplicar overrides persistidos", @"Forçar helpers LiquidGlass", @"Preset DogFood/Internal", @"Limpar todos MC overrides"];
    NSArray *subs = @[@"MobileConfig bridge", @"RAM cache", @"SDK26 helpers", @"slots internos", @"remove fbgr.slot.*"];
    UIColor *color = ip.row == 4 ? UIColor.systemRedColor : FBGRAccentColor();
    NSArray *icons = @[@"bolt.fill", @"arrow.clockwise", @"sparkles", @"ladybug.fill", @"trash"];
    FBGRConfigureCell(c, titles[(NSUInteger)ip.row], subs[(NSUInteger)ip.row], FBGRSymbol(icons[(NSUInteger)ip.row], color));
    c.textLabel.textColor = ip.row == 4 ? UIColor.systemRedColor : FBGRTextColor();
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 0) {
        FBGRFeatureCategory cat = (FBGRFeatureCategory)[FBGRCategories()[(NSUInteger)ip.row] integerValue];
        [self.navigationController pushViewController:[[FBGRGateCategoryVC alloc] initWithCategory:cat] animated:YES];
        return;
    }

    if (ip.section == 1) {
        if (ip.row == 0) [self.navigationController pushViewController:[FBGRGateRuntimeBrowserVC new] animated:YES];
        else [self.navigationController pushViewController:[[FBGRBoolRuntimeBrowserVC alloc] initWithImageKind:ip.row == 1 ? FBGRBoolRuntimeImageKindExecutable : FBGRBoolRuntimeImageKindFBSharedFramework] animated:YES];
        return;
    }

    if (ip.row == 0) {
        FBGRMCGateHooksEnsureInstalled();
        [self alert:@"MobileConfig hooks" msg:FBGRMCGateHooksDiagnostic()];
    } else if (ip.row == 1) {
        FBGRMCGateHooksApplyPersistedOverrides();
        [self alert:@"Overrides" msg:FBGRMCGateHooksDiagnostic()];
    } else if (ip.row == 2) {
        FBGRLiquidGlassSetForced(YES);
        [self alert:@"LiquidGlass" msg:FBGRLiquidGlassDiagnostic()];
    } else if (ip.row == 3) {
        FBGRDogFoodSetEnabled(YES);
        FBGRMCGateHooksEnsureInstalled();
        [self alert:@"DogFood" msg:FBGRDogFoodDiagnostic()];
    } else {
        FBGRGateClearAll();
        [self.tableView reloadData];
    }
}

- (void)alert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg ?: @"" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

void FBGRPresentMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { root = w.rootViewController; break; }
                }
                if (root) break;
            }
        }
        if (!root) root = UIApplication.sharedApplication.keyWindow.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;

        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[FBGRSurfaceListVC new]];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [root presentViewController:nav animated:YES completion:nil];
    });
}
