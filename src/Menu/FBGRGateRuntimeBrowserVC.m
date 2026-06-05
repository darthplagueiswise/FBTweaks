#import "FBGRGateRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"

extern void FBGRMCGateHooksEnsureInstalled(void);

@interface FBGRGateRuntimeBrowserVC () <UISearchResultsUpdating>
@property(nonatomic, strong) NSArray<FBGRMCParam *> *visible;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, assign) FBGRFeatureCategory category;
@end

@implementation FBGRGateRuntimeBrowserVC
- (instancetype)init { if(!(self=[super initWithStyle:UITableViewStyleInsetGrouped]))return nil; self.title=@"MC Runtime"; _category=FBGRFeatureCategoryAll; return self; }
- (void)viewDidLoad { [super viewDidLoad]; FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView); self.search=[[UISearchController alloc] initWithSearchResultsController:nil]; self.search.searchResultsUpdater=self; FBGRApplySearchController(self.search); self.navigationItem.searchController=self.search; [[FBGRMCCatalog shared] loadIfNeeded]; [self reload]; }
- (void)reload { self.visible=[[FBGRMCCatalog shared] search:self.search.searchBar.text category:self.category]; [self.tableView reloadData]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.visible.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return [NSString stringWithFormat:@"%lu bool params reais. Fonte: %@", (unsigned long)self.visible.count, [FBGRMCCatalog shared].sourceDescription ?: @"?"]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip { UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"mc"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mc"]; FBGRApplyGlassCell(c); FBGRMCParam *p=self.visible[ip.row]; BOOL set=FBGRGateIsSet(p.slotId); c.textLabel.text=p.fullKey; c.detailTextLabel.text=[NSString stringWithFormat:@"%@ · slot=%llu · default=%@%@", FBGRFeatureCategoryTitle(p.category), (unsigned long long)p.slotId, p.defaultBool?@"YES":@"NO", set?[NSString stringWithFormat:@" · FORÇADO %@", FBGRGateGet(p.slotId)?@"YES":@"NO"]:@""]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return c; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; FBGRMCParam *p=self.visible[ip.row]; UIAlertController *a=[UIAlertController alertControllerWithTitle:p.fullKey message:[NSString stringWithFormat:@"slot=%llu\ncategory=%@",(unsigned long long)p.slotId,FBGRFeatureCategoryTitle(p.category)] preferredStyle:UIAlertControllerStyleActionSheet]; [a addAction:[UIAlertAction actionWithTitle:@"Force YES" style:UIAlertActionStyleDefault handler:^(__unused id x){ FBGRGateSet(p.slotId, YES); FBGRMCGateHooksEnsureInstalled(); [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Force NO" style:UIAlertActionStyleDefault handler:^(__unused id x){ FBGRGateSet(p.slotId, NO); FBGRMCGateHooksEnsureInstalled(); [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Clear override" style:UIAlertActionStyleDestructive handler:^(__unused id x){ FBGRGateClear(p.slotId); [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end
