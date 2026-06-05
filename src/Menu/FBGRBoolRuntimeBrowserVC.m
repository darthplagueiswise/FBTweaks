#import "FBGRBoolRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"

@interface FBGRBoolRuntimeBrowserVC () <UISearchResultsUpdating>
@property(nonatomic, assign) FBGRBoolRuntimeImageKind kind;
@property(nonatomic, strong) NSArray<FBGRBoolRuntimeItem *> *all;
@property(nonatomic, strong) NSArray<FBGRBoolRuntimeItem *> *visible;
@property(nonatomic, strong) UISearchController *search;
@end

@implementation FBGRBoolRuntimeBrowserVC
- (instancetype)initWithImageKind:(FBGRBoolRuntimeImageKind)kind { if(!(self=[super initWithStyle:UITableViewStyleInsetGrouped]))return nil; _kind=kind; self.title=kind==FBGRBoolRuntimeImageKindExecutable?@"Executable Bool Runtime":@"FBShared Bool Runtime"; return self; }
- (void)viewDidLoad { [super viewDidLoad]; FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView); self.search=[[UISearchController alloc] initWithSearchResultsController:nil]; self.search.searchResultsUpdater=self; FBGRApplySearchController(self.search); self.navigationItem.searchController=self.search; self.all=[FBGRBoolRuntimeInventory scanImageKind:self.kind]; [self reload]; }
- (void)reload { NSString *q=self.search.searchBar.text.lowercaseString; if(!q.length){self.visible=self.all;} else { NSMutableArray *m=[NSMutableArray array]; for(FBGRBoolRuntimeItem *i in self.all) if([i.className.lowercaseString containsString:q]||[i.selectorName.lowercaseString containsString:q]) [m addObject:i]; self.visible=m; } [self.tableView reloadData]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.visible.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return @"Scanner real do runtime ObjC: class_getImageName + class_copyMethodList + method_copyReturnType. Hook patchável via MSHookMessageEx."; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip { UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"bool"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"bool"]; FBGRApplyGlassCell(c); FBGRBoolRuntimeItem *i=self.visible[ip.row]; c.textLabel.text=[NSString stringWithFormat:@"%@[%@ %@]", i.classMethod?@"+":@"-", i.className, i.selectorName]; c.detailTextLabel.text=[NSString stringWithFormat:@"%@%@", i.hooked?@"HOOKED ":@"", i.overrideSet?(i.overrideValue?@"FORCE YES":@"FORCE NO"):@"no override"]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return c; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; FBGRBoolRuntimeItem *item=self.visible[ip.row]; UIAlertController *a=[UIAlertController alertControllerWithTitle:item.selectorName message:item.className preferredStyle:UIAlertControllerStyleActionSheet]; [a addAction:[UIAlertAction actionWithTitle:@"Force YES" style:UIAlertActionStyleDefault handler:^(__unused id x){ [FBGRBoolRuntimeInventory setOverrideForItem:item value:YES]; [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Force NO" style:UIAlertActionStyleDefault handler:^(__unused id x){ [FBGRBoolRuntimeInventory setOverrideForItem:item value:NO]; [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Install hook sem override" style:UIAlertActionStyleDefault handler:^(__unused id x){ [FBGRBoolRuntimeInventory installHookForItem:item]; item.hooked=YES; [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Clear override" style:UIAlertActionStyleDestructive handler:^(__unused id x){ [FBGRBoolRuntimeInventory clearOverrideForItem:item]; [self reload]; }]]; [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end
