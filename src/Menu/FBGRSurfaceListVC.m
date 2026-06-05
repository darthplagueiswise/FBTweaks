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

static NSArray<NSNumber *> *FBGRCategories(void) {
    return @[@(FBGRFeatureCategoryUI), @(FBGRFeatureCategoryLiquidGlass), @(FBGRFeatureCategoryTabBar), @(FBGRFeatureCategoryDating), @(FBGRFeatureCategoryExperiments), @(FBGRFeatureCategoryDogfood), @(FBGRFeatureCategoryInternal), @(FBGRFeatureCategoryDebug), @(FBGRFeatureCategoryMarketplace), @(FBGRFeatureCategoryAI)];
}

@implementation FBGRSurfaceListVC
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"FBTweaks"; FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView); [[FBGRMCCatalog shared] loadIfNeeded]; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Logs" style:UIBarButtonItemStylePlain target:self action:@selector(logs)]; }
- (void)logs { [self.navigationController pushViewController:[FBGRLogViewController new] animated:YES]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { if(section==0)return FBGRCategories().count; if(section==1)return 3; return 5; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section { return section==0?@"Feature Flags":section==1?@"Runtime real":@"Ações"; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { if(section==0)return [NSString stringWithFormat:@"Metadata: %lu BOOL flags · %@", (unsigned long)[FBGRMCCatalog shared].boolParams.count, [FBGRMCCatalog shared].sourceDescription ?: @"?"]; if(section==1)return @"Executable e FBShared usam scanner ObjC real e patch via MSHookMessageEx."; return nil; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip { UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"cell"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"]; FBGRApplyGlassCell(c); c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; c.imageView.image=nil; c.detailTextLabel.text=nil; if(ip.section==0){ FBGRFeatureCategory cat=(FBGRFeatureCategory)[FBGRCategories()[ip.row] integerValue]; c.textLabel.text=FBGRFeatureCategoryTitle(cat); c.imageView.image=FBGRSymbol(FBGRFeatureCategoryIcon(cat), FBGRAccentColor()); c.detailTextLabel.text=[NSString stringWithFormat:@"%lu flags", (unsigned long)[[FBGRMCCatalog shared] paramsForCategory:cat].count]; } else if(ip.section==1){ NSArray *titles=@[@"MobileConfig Runtime Browser",@"Executable Bool Runtime — Facebook",@"FBSharedFramework Bool Runtime"]; NSArray *subs=@[@"ReactMobileConfigMetadata real, patchável por slotId",@"Varre /Facebook.app/Facebook",@"Varre /FBSharedFramework.framework/FBSharedFramework"]; c.textLabel.text=titles[ip.row]; c.detailTextLabel.text=subs[ip.row]; c.imageView.image=FBGRSymbol(ip.row==0?@"slider.horizontal.3":@"cpu", FBGRAccentColor()); } else { NSArray *titles=@[@"Instalar hooks MobileConfig",@"Aplicar overrides persistidos",@"Forçar helpers LiquidGlass",@"Preset DogFood/Internal",@"Limpar todos MC overrides"]; c.textLabel.text=titles[ip.row]; c.imageView.image=FBGRSymbol(@[@"bolt.fill",@"arrow.clockwise",@"sparkles",@"ladybug.fill",@"trash"][ip.row], ip.row==4?UIColor.systemRedColor:FBGRAccentColor()); if(ip.row==4)c.textLabel.textColor=UIColor.systemRedColor; } return c; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; if(ip.section==0){ FBGRFeatureCategory cat=(FBGRFeatureCategory)[FBGRCategories()[ip.row] integerValue]; [self.navigationController pushViewController:[[FBGRGateCategoryVC alloc] initWithCategory:cat] animated:YES]; } else if(ip.section==1){ if(ip.row==0)[self.navigationController pushViewController:[FBGRGateRuntimeBrowserVC new] animated:YES]; else [self.navigationController pushViewController:[[FBGRBoolRuntimeBrowserVC alloc] initWithImageKind:ip.row==1?FBGRBoolRuntimeImageKindExecutable:FBGRBoolRuntimeImageKindFBSharedFramework] animated:YES]; } else { if(ip.row==0){ FBGRMCGateHooksEnsureInstalled(); [self alert:@"MobileConfig" msg:FBGRMCGateHooksDiagnostic() ?: @"Instalando hooks..."]; } else if(ip.row==1){ FBGRMCGateHooksApplyPersistedOverrides(); [self alert:@"Overrides" msg:@"Overrides persistidos aquecidos e hooks MC solicitados se houver override."]; } else if(ip.row==2){ FBGRLiquidGlassSetForced(YES); [self alert:@"LiquidGlass" msg:FBGRLiquidGlassDiagnostic() ?: @"Solicitado"]; } else if(ip.row==3){ FBGRDogFoodSetEnabled(YES); [self alert:@"DogFood" msg:@"Preset aplicado em flags MC reais. Agora instala MC hooks se necessário."]; FBGRMCGateHooksEnsureInstalled(); } else { FBGRGateClearAll(); [self.tableView reloadData]; } } }
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
