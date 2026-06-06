#import "FBGRGateRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"

extern void FBGRMCGateHooksEnsureInstalled(void);
extern void FBGRMCGateCacheRefresh(void);
extern NSString *FBGRMCGateHooksDiagnostic(void);

@interface FBGRGateRuntimeBrowserVC () <UISearchResultsUpdating>
@property(nonatomic, strong) NSArray<FBGRMCParam *> *visible;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, assign) FBGRFeatureCategory category;
@end

@implementation FBGRGateRuntimeBrowserVC
- (instancetype)init { if(!(self=[super initWithStyle:UITableViewStyleInsetGrouped]))return nil; self.title=@"MC Runtime"; _category=FBGRFeatureCategoryAll; return self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView); self.tableView.estimatedRowHeight=44.0;
    self.search=[[UISearchController alloc] initWithSearchResultsController:nil]; self.search.searchResultsUpdater=self; FBGRApplySearchController(self.search); self.navigationItem.searchController=self.search; self.navigationItem.hidesSearchBarWhenScrolling=YES;
    [self configureToolbarButtons]; [[FBGRMCCatalog shared] loadIfNeeded]; [self reload];
}
- (void)configureToolbarButtons { UIBarButtonItem *restart=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"power"] style:UIBarButtonItemStylePlain target:self action:@selector(restartApp)]; UIBarButtonItem *apply=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(applyHooks)]; UIBarButtonItem *searchButton=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"] style:UIBarButtonItemStylePlain target:self action:@selector(showSearch)]; UIBarButtonItem *clearButton=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(clearVisible)]; self.navigationItem.rightBarButtonItems=@[restart,apply,searchButton,clearButton]; }
- (void)showSearch { self.search.active=YES; [self.search.searchBar becomeFirstResponder]; }
- (void)restartApp { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); }); }
- (void)applyHooks { FBGRMCGateHooksEnsureInstalled(); FBGRMCGateCacheRefresh(); [self alert:@"Hooks" msg:FBGRMCGateHooksDiagnostic() ?: @"Hooks solicitados."]; [self reload]; }
- (void)clearVisible { for (FBGRMCParam *p in self.visible) FBGRGateClear(p.slotId); FBGRMCGateCacheRefresh(); [self reload]; }
- (void)reload { self.visible=[[FBGRMCCatalog shared] search:self.search.searchBar.text category:self.category]; [self.tableView reloadData]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.visible.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return [NSString stringWithFormat:@"%lu flags · ✓ aplica hooks · ⏻ reinicia", (unsigned long)self.visible.count]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"mc"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mc"];
    FBGRMCParam *p=self.visible[ip.row]; BOOL set=FBGRGateIsSet(p.slotId); BOOL val=set?FBGRGateGet(p.slotId):p.defaultBool;
    NSString *detail=[NSString stringWithFormat:@"%@ · slot=%llu · default=%@%@", FBGRFeatureCategoryTitle(p.category), (unsigned long long)p.slotId, p.defaultBool?@"YES":@"NO", set?[NSString stringWithFormat:@" → %@", val?@"YES":@"NO"]:@""];
    FBGRApplyReadableTextCellWithReservedTrailing(c, p.fullKey, detail, 58.0);
    UISwitch *sw=[UISwitch new]; sw.on=val; sw.tag=ip.row; FBGRConfigureCompactSwitch(sw); [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; FBGRInstallSwitchInCell(c, sw); c.selectionStyle=UITableViewCellSelectionStyleNone; return c;
}
- (void)toggle:(UISwitch *)sw { if (sw.tag >= self.visible.count) return; FBGRMCParam *p=self.visible[sw.tag]; FBGRGateSet(p.slotId, sw.isOn); FBGRMCGateHooksEnsureInstalled(); FBGRMCGateCacheRefresh(); [self reload]; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; FBGRMCParam *p=self.visible[ip.row]; UIAlertController *a=[UIAlertController alertControllerWithTitle:p.fullKey message:[NSString stringWithFormat:@"slot=%llu\n%@",(unsigned long long)p.slotId,FBGRFeatureCategoryTitle(p.category)] preferredStyle:UIAlertControllerStyleActionSheet]; [a addAction:[UIAlertAction actionWithTitle:@"Clear override" style:UIAlertActionStyleDestructive handler:^(__unused id x){ FBGRGateClear(p.slotId); FBGRMCGateCacheRefresh(); [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)alert:(NSString *)title msg:(NSString *)msg { UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end
