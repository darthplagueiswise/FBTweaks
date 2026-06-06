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

extern void FBGRMCGateHooksEnsureInstalled(void);
extern void FBGRMCGateHooksApplyPersistedOverrides(void);
extern NSString *FBGRMCGateHooksDiagnostic(void);
extern void FBGRLiquidGlassEnsureInstalled(void);
extern void FBGRLiquidGlassSetForced(BOOL forced);
extern NSString *FBGRLiquidGlassDiagnostic(void);
extern void FBGRDogFoodSetEnabled(BOOL enabled);
extern NSString *FBGRGateDiagnostic(void);

static NSArray<NSNumber *> *FBGRCategories(void) {
    return @[@(FBGRFeatureCategoryUI), @(FBGRFeatureCategoryLiquidGlass), @(FBGRFeatureCategoryTabBar), @(FBGRFeatureCategoryDating), @(FBGRFeatureCategoryExperiments), @(FBGRFeatureCategoryDogfood), @(FBGRFeatureCategoryInternal), @(FBGRFeatureCategoryDebug), @(FBGRFeatureCategoryMarketplace), @(FBGRFeatureCategoryAI)];
}

@implementation FBGRSurfaceListVC
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"FBTweaks"; FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView); [[FBGRMCCatalog shared] loadIfNeeded]; [self configureToolbarButtons]; }
- (void)configureToolbarButtons { UIBarButtonItem *restart=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"power"] style:UIBarButtonItemStylePlain target:self action:@selector(restartApp)]; UIBarButtonItem *apply=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(applyAll)]; UIBarButtonItem *logs=[[UIBarButtonItem alloc] initWithTitle:@"Logs" style:UIBarButtonItemStylePlain target:self action:@selector(logs)]; self.navigationItem.rightBarButtonItems=@[restart,apply,logs]; }
- (void)restartApp { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); }); }
- (void)applyAll { FBGRMCGateHooksApplyPersistedOverrides(); NSUInteger n=[FBGRBoolRuntimeInventory reinstallPersistedHooks]; [self alert:@"Aplicar hooks" msg:[NSString stringWithFormat:@"%@\n\nruntimeReinstalled=%lu\n%@", FBGRMCGateHooksDiagnostic() ?: @"MC n/a", (unsigned long)n, [FBGRBoolRuntimeInventory diagnostic] ?: @""]]; }
- (void)logs { [self.navigationController pushViewController:[FBGRLogViewController new] animated:YES]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { if(section==0)return FBGRCategories().count; if(section==1)return 3; return 6; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section { return section==0?@"Feature Flags":section==1?@"Runtime real":@"Ações"; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { if(section==0)return [NSString stringWithFormat:@"Metadata: %lu BOOL flags · %@", (unsigned long)[FBGRMCCatalog shared].boolParams.count, [FBGRMCCatalog shared].sourceDescription ?: @"?"]; if(section==1)return @"Runtime browsers têm busca, aplicar hooks e reiniciar no topo."; return nil; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip { UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"cell"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"]; FBGRApplyGlassCell(c); c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; c.imageView.image=nil; c.detailTextLabel.text=nil; c.textLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]; c.detailTextLabel.font=[UIFont systemFontOfSize:8 weight:UIFontWeightRegular]; if(ip.section==0){ FBGRFeatureCategory cat=(FBGRFeatureCategory)[FBGRCategories()[ip.row] integerValue]; c.textLabel.text=FBGRFeatureCategoryTitle(cat); c.imageView.image=FBGRSymbol(FBGRFeatureCategoryIcon(cat), FBGRTextColor()); c.detailTextLabel.text=[NSString stringWithFormat:@"%lu flags", (unsigned long)[[FBGRMCCatalog shared] paramsForCategory:cat].count]; } else if(ip.section==1){ NSArray *titles=@[@"MobileConfig Runtime Browser",@"Executable Bool Runtime",@"FBSharedFramework Bool Runtime"]; NSArray *subs=@[@"ReactMobileConfigMetadata real, patchável por slotId",@"Varre /Facebook.app/Facebook",@"Varre /FBSharedFramework.framework/FBSharedFramework"]; c.textLabel.text=titles[ip.row]; c.detailTextLabel.text=subs[ip.row]; c.imageView.image=FBGRSymbol(ip.row==0?@"slider.horizontal.3":@"cpu", FBGRTextColor()); } else { NSArray *titles=@[@"Instalar hooks MobileConfig",@"Aplicar overrides persistidos",@"Forçar helpers LiquidGlass",@"Preset DogFood/Internal",@"Limpar todos overrides",@"Reiniciar Facebook"]; c.textLabel.text=titles[ip.row]; c.imageView.image=FBGRSymbol(@[@"bolt.fill",@"arrow.clockwise",@"sparkles",@"ladybug.fill",@"trash",@"power"][ip.row], ip.row>=4?UIColor.systemRedColor:FBGRTextColor()); if(ip.row>=4)c.textLabel.textColor=UIColor.systemRedColor; } return c; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; if(ip.section==0){ FBGRFeatureCategory cat=(FBGRFeatureCategory)[FBGRCategories()[ip.row] integerValue]; [self.navigationController pushViewController:[[FBGRGateCategoryVC alloc] initWithCategory:cat] animated:YES]; } else if(ip.section==1){ if(ip.row==0)[self.navigationController pushViewController:[FBGRGateRuntimeBrowserVC new] animated:YES]; else [self.navigationController pushViewController:[[FBGRBoolRuntimeBrowserVC alloc] initWithImageKind:ip.row==1?FBGRBoolRuntimeImageKindExecutable:FBGRBoolRuntimeImageKindFBSharedFramework] animated:YES]; } else { if(ip.row==0){ FBGRMCGateHooksEnsureInstalled(); [self alert:@"MobileConfig" msg:FBGRMCGateHooksDiagnostic() ?: @"Instalando hooks..."]; } else if(ip.row==1){ [self applyAll]; } else if(ip.row==2){ FBGRLiquidGlassSetForced(YES); [self alert:@"LiquidGlass" msg:FBGRLiquidGlassDiagnostic() ?: @"Solicitado"]; } else if(ip.row==3){ FBGRDogFoodSetEnabled(YES); [self alert:@"DogFood" msg:@"Preset aplicado em flags MC reais. Agora instala MC hooks se necessário."]; FBGRMCGateHooksEnsureInstalled(); } else if(ip.row==4){ FBGRGateClearAll(); [self alert:@"Reset" msg:@"Overrides MC, runtime BOOL, índices de hooks e LiquidGlass forçado foram removidos. Reinicie o Facebook para descarregar hooks já instalados."]; [self.tableView reloadData]; } else { [self restartApp]; } } }
- (void)alert:(NSString *)title msg:(NSString *)msg { UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end

void FBGRPresentMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) { root = w.rootViewController; break; }
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
