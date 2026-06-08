#import "FBGRGateRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Hooks/FBGRHookExports.h"

extern NSString *FBGRMCGateHooksDiagnostic(void);

@interface FBGRGateRuntimeBrowserVC () <UISearchResultsUpdating>
@property(nonatomic, strong) NSArray<FBGRMCParam *> *visible;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, assign) FBGRFeatureCategory category;
@end

@implementation FBGRGateRuntimeBrowserVC
- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"MC Runtime";
    _category = FBGRFeatureCategoryAll;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    FBGRApplyGlassController(self);
    FBGRApplyGlassTable(self.tableView);
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    FBGRApplySearchController(self.search);
    self.navigationItem.searchController = self.search;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Hooks" style:UIBarButtonItemStylePlain target:self action:@selector(hooks)];
    [[FBGRMCCatalog shared] loadIfNeeded];
    [self reload];
}

- (void)hooks {
    FBGRMCGateHooksEnsureInstalled();
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"MobileConfig hooks" message:FBGRMCGateHooksDiagnostic() preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)reload {
    self.visible = [[FBGRMCCatalog shared] search:self.search.searchBar.text category:self.category];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.visible.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return nil; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"mc"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mc"];

    FBGRMCParam *p = self.visible[(NSUInteger)ip.row];
    BOOL set = FBGRGateIsSet(p.slotId);
    BOOL val = set ? FBGRGateGet(p.slotId) : p.defaultBool;

    UISwitch *sw = [UISwitch new];
    sw.on = val;
    sw.tag = ip.row;
    sw.onTintColor = FBGRAccentColor();
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];

    NSString *subtitle = [NSString stringWithFormat:@"%@ · slot %llu · default %@%@",
                          FBGRFeatureCategoryTitle(p.category),
                          (unsigned long long)p.slotId,
                          p.defaultBool ? @"YES" : @"NO",
                          set ? [NSString stringWithFormat:@" · override %@", val ? @"ON" : @"OFF"] : @""];
    FBGRConfigureSwitchCell(c, p.fullKey, subtitle, sw, nil);
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (void)toggle:(UISwitch *)sw {
    FBGRMCParam *p = self.visible[(NSUInteger)sw.tag];
    FBGRGateSet(p.slotId, sw.isOn);
    FBGRMCGateHooksEnsureInstalled();
    NSIndexPath *ip = [NSIndexPath indexPathForRow:sw.tag inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}
@end
