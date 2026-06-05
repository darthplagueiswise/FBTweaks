#import "FBGRGateRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"

extern void FBGRMCGateHooksEnsureInstalled(void);
extern void FBGRMCGateCacheRefresh(void);

@interface FBGRGateRuntimeBrowserVC () <UISearchResultsUpdating>
@property(nonatomic, strong) NSArray<FBGRMCParam *> *visible;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, assign) FBGRFeatureCategory category;
@end

@implementation FBGRGateRuntimeBrowserVC
- (instancetype)init { if(!(self=[super initWithStyle:UITableViewStyleInsetGrouped]))return nil; self.title=@"MC Runtime"; _category=FBGRFeatureCategoryAll; return self; }
- (void)viewDidLoad { [super viewDidLoad]; FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView); self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=96.0; self.search=[[UISearchController alloc] initWithSearchResultsController:nil]; self.search.searchResultsUpdater=self; FBGRApplySearchController(self.search); self.navigationItem.searchController=self.search; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Limpar" style:UIBarButtonItemStylePlain target:self action:@selector(clearVisible)]; [[FBGRMCCatalog shared] loadIfNeeded]; [self reload]; }
- (void)clearVisible { for (FBGRMCParam *p in self.visible) FBGRGateClear(p.slotId); FBGRMCGateCacheRefresh(); [self reload]; }
- (void)reload { self.visible=[[FBGRMCCatalog shared] search:self.search.searchBar.text category:self.category]; [self.tableView reloadData]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.visible.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return [NSString stringWithFormat:@"%lu flags. O switch aplica Force YES/NO e instala hooks MC real scan.", (unsigned long)self.visible.count]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"mc"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mc"];
    FBGRMCParam *p=self.visible[ip.row]; BOOL set=FBGRGateIsSet(p.slotId); BOOL val=set?FBGRGateGet(p.slotId):p.defaultBool;
    NSString *detail=[NSString stringWithFormat:@"%@ · slot=%llu · default=%@%@", FBGRFeatureCategoryTitle(p.category), (unsigned long long)p.slotId, p.defaultBool?@"YES":@"NO", set?[NSString stringWithFormat:@" · FORÇADO %@", val?@"YES":@"NO"]:@""];
    FBGRApplyReadableTextCell(c, p.fullKey, detail);
    UISwitch *sw=[UISwitch new]; sw.on=val; sw.tag=ip.row; sw.onTintColor=FBGRAccentColor(); [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=sw; c.selectionStyle=UITableViewCellSelectionStyleNone; return c;
}
- (void)toggle:(UISwitch *)sw { FBGRMCParam *p=self.visible[sw.tag]; FBGRGateSet(p.slotId, sw.isOn); FBGRMCGateHooksEnsureInstalled(); FBGRMCGateCacheRefresh(); NSIndexPath *ip=[NSIndexPath indexPathForRow:sw.tag inSection:0]; [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone]; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; FBGRMCParam *p=self.visible[ip.row]; UIAlertController *a=[UIAlertController alertControllerWithTitle:p.fullKey message:[NSString stringWithFormat:@"slot=%llu\n%@",(unsigned long long)p.slotId,FBGRFeatureCategoryTitle(p.category)] preferredStyle:UIAlertControllerStyleActionSheet]; [a addAction:[UIAlertAction actionWithTitle:@"Clear override" style:UIAlertActionStyleDestructive handler:^(__unused id x){ FBGRGateClear(p.slotId); FBGRMCGateCacheRefresh(); [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end
