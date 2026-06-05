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
- (void)viewDidLoad { [super viewDidLoad]; FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView); self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=104.0; self.search=[[UISearchController alloc] initWithSearchResultsController:nil]; self.search.searchResultsUpdater=self; FBGRApplySearchController(self.search); self.navigationItem.searchController=self.search; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Limpar" style:UIBarButtonItemStylePlain target:self action:@selector(clearVisible)]; self.all=[FBGRBoolRuntimeInventory scanImageKind:self.kind]; [self reload]; }
- (void)clearVisible { for (FBGRBoolRuntimeItem *i in self.visible) [FBGRBoolRuntimeInventory clearOverrideForItem:i]; [self reload]; }
- (void)reload { NSString *q=self.search.searchBar.text.lowercaseString; if(!q.length){self.visible=self.all;} else { NSMutableArray *m=[NSMutableArray array]; for(FBGRBoolRuntimeItem *i in self.all) if([i.className.lowercaseString containsString:q]||[i.selectorName.lowercaseString containsString:q]) [m addObject:i]; self.visible=m; } [self.tableView reloadData]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.visible.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return @"Switch OFF = Force NO. Switch ON = Force YES. Toque na linha para limpar override. O hook é instalado no toggle."; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"bool"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"bool"];
    FBGRBoolRuntimeItem *i=self.visible[ip.row];
    NSString *title=[NSString stringWithFormat:@"%@[%@ %@]", i.classMethod?@"+":@"-", i.className, i.selectorName];
    NSString *detail=[NSString stringWithFormat:@"%@%@%@", i.imageName.lastPathComponent ?: @"", i.hooked?@" · HOOKED":@"", i.overrideSet?(i.overrideValue?@" · FORCE YES":@" · FORCE NO"):@" · sem override"];
    FBGRApplyReadableTextCell(c, title, detail);
    UISwitch *sw=[UISwitch new]; sw.on=i.overrideSet ? i.overrideValue : NO; sw.tag=ip.row; sw.onTintColor=FBGRAccentColor(); [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=sw; c.selectionStyle=UITableViewCellSelectionStyleDefault; return c;
}
- (void)toggle:(UISwitch *)sw { FBGRBoolRuntimeItem *item=self.visible[sw.tag]; [FBGRBoolRuntimeInventory setOverrideForItem:item value:sw.isOn]; NSIndexPath *ip=[NSIndexPath indexPathForRow:sw.tag inSection:0]; [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone]; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; FBGRBoolRuntimeItem *item=self.visible[ip.row]; [FBGRBoolRuntimeInventory clearOverrideForItem:item]; [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone]; }
@end
