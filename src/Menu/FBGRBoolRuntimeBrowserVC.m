#import "FBGRBoolRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"

@interface FBGRBoolRuntimeBrowserVC () <UISearchResultsUpdating>
@property(nonatomic, assign) FBGRBoolRuntimeImageKind kind;
@property(nonatomic, strong) NSArray<FBGRBoolRuntimeItem *> *all;
@property(nonatomic, strong) NSArray<FBGRBoolRuntimeItem *> *visible;
@property(nonatomic, strong) UISearchController *search;
@end

@implementation FBGRBoolRuntimeBrowserVC
- (instancetype)initWithImageKind:(FBGRBoolRuntimeImageKind)kind { if(!(self=[super initWithStyle:UITableViewStyleInsetGrouped]))return nil; _kind=kind; self.title=kind==FBGRBoolRuntimeImageKindExecutable?@"Executable Bool":@"FBShared Bool"; return self; }
- (void)viewDidLoad { [super viewDidLoad]; FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView); self.tableView.estimatedRowHeight=44.0; self.search=[[UISearchController alloc] initWithSearchResultsController:nil]; self.search.searchResultsUpdater=self; FBGRApplySearchController(self.search); self.navigationItem.searchController=self.search; self.navigationItem.hidesSearchBarWhenScrolling=YES; [self configureToolbarButtons]; self.all=[FBGRBoolRuntimeInventory scanImageKind:self.kind]; [self reload]; }
- (void)configureToolbarButtons { UIBarButtonItem *restart=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"power"] style:UIBarButtonItemStylePlain target:self action:@selector(restartApp)]; UIBarButtonItem *apply=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(applyHooks)]; UIBarButtonItem *searchButton=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"] style:UIBarButtonItemStylePlain target:self action:@selector(showSearch)]; UIBarButtonItem *clearButton=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(clearVisible)]; self.navigationItem.rightBarButtonItems=@[restart,apply,searchButton,clearButton]; }
- (void)showSearch { self.search.active=YES; [self.search.searchBar becomeFirstResponder]; }
- (void)restartApp { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); }); }
- (void)applyHooks { NSUInteger visibleInstalled=0; for (FBGRBoolRuntimeItem *i in self.visible) if (i.overrideSet) { [FBGRBoolRuntimeInventory installHookForItem:i]; visibleInstalled++; } NSUInteger persisted=[FBGRBoolRuntimeInventory reinstallPersistedHooks]; [self alert:@"Runtime hooks" msg:[NSString stringWithFormat:@"visible=%lu\npersisted=%lu\n%@", (unsigned long)visibleInstalled, (unsigned long)persisted, [FBGRBoolRuntimeInventory diagnostic] ?: @""]]; [self reload]; }
- (void)clearVisible { for (FBGRBoolRuntimeItem *i in self.visible) [FBGRBoolRuntimeInventory clearOverrideForItem:i]; [self reload]; }
- (void)reload { NSString *q=self.search.searchBar.text.lowercaseString ?: @""; if(!q.length){self.visible=self.all;} else { NSMutableArray *m=[NSMutableArray array]; for(FBGRBoolRuntimeItem *i in self.all) if([i.className.lowercaseString containsString:q]||[i.selectorName.lowercaseString containsString:q]||[i.imageName.lowercaseString containsString:q]) [m addObject:i]; self.visible=m; } [self.tableView reloadData]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.visible.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return @"✓ aplica hooks dos overrides visíveis/persistidos. ⏻ reinicia para aplicar processo limpo."; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"bool"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"bool"];
    FBGRBoolRuntimeItem *i=self.visible[ip.row];
    NSString *title=[NSString stringWithFormat:@"%@ %@", i.className ?: @"", i.selectorName ?: @""];
    NSString *detail=[NSString stringWithFormat:@"%@%@%@", i.classMethod?@"class":@"inst", i.hooked?@" · hooked":@"", i.overrideSet?(i.overrideValue?@" · YES":@" · NO"):@" · no override"];
    FBGRApplyReadableTextCellWithReservedTrailing(c, title, detail, 58.0);
    UISwitch *sw=[UISwitch new]; sw.on=i.overrideSet ? i.overrideValue : NO; sw.tag=ip.row; FBGRConfigureCompactSwitch(sw); [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; FBGRInstallSwitchInCell(c, sw); c.selectionStyle=UITableViewCellSelectionStyleDefault; return c;
}
- (void)toggle:(UISwitch *)sw { if (sw.tag >= self.visible.count) return; FBGRBoolRuntimeItem *item=self.visible[sw.tag]; [FBGRBoolRuntimeInventory setOverrideForItem:item value:sw.isOn]; [self reload]; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; FBGRBoolRuntimeItem *item=self.visible[ip.row]; [FBGRBoolRuntimeInventory clearOverrideForItem:item]; [self reload]; }
- (void)alert:(NSString *)title msg:(NSString *)msg { UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end
