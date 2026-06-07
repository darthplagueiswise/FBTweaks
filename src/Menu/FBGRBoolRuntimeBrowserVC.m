#import "FBGRBoolRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"

@interface FBGRBoolRuntimeBrowserVC () <UISearchResultsUpdating>
@property(nonatomic, assign) FBGRBoolRuntimeImageKind kind;
@property(nonatomic, strong) NSArray<FBGRBoolRuntimeItem *> *all;
@property(nonatomic, strong) NSArray<FBGRBoolRuntimeItem *> *visible;
@property(nonatomic, strong) UISearchController *search;
@end

@implementation FBGRBoolRuntimeBrowserVC
- (instancetype)initWithImageKind:(FBGRBoolRuntimeImageKind)kind {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _kind = kind;
    self.title = kind == FBGRBoolRuntimeImageKindExecutable ? @"Executable Runtime" : @"FBShared Runtime";
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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Revarrer" style:UIBarButtonItemStylePlain target:self action:@selector(rescan)];
    [self rescan];
}

- (void)rescan {
    self.all = [FBGRBoolRuntimeInventory scanImageKind:self.kind];
    [self reload];
}

- (void)reload {
    NSString *q = self.search.searchBar.text.lowercaseString;
    if (!q.length) {
        self.visible = self.all;
    } else {
        NSMutableArray *m = [NSMutableArray array];
        for (FBGRBoolRuntimeItem *i in self.all) {
            if ([i.className.lowercaseString containsString:q] || [i.selectorName.lowercaseString containsString:q]) [m addObject:i];
        }
        self.visible = m;
    }
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reload]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.visible.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return nil; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"bool"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"bool"];

    FBGRBoolRuntimeItem *i = self.visible[(NSUInteger)ip.row];
    UISwitch *sw = [UISwitch new];
    sw.on = i.overrideSet ? i.overrideValue : NO;
    sw.tag = ip.row;
    sw.onTintColor = FBGRAccentColor();
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];

    NSString *title = [NSString stringWithFormat:@"%@ %@", i.classMethod ? @"+" : @"-", i.selectorName];
    NSString *subtitle = [NSString stringWithFormat:@"%@ · %@",
                          i.className ?: @"?",
                          i.overrideSet ? (i.overrideValue ? @"override ON" : @"override OFF") : (i.hooked ? @"hooked" : @"sem override")];
    FBGRConfigureSwitchCell(c, title, subtitle, sw, nil);
    return c;
}

- (void)toggle:(UISwitch *)sw {
    FBGRBoolRuntimeItem *item = self.visible[(NSUInteger)sw.tag];
    [FBGRBoolRuntimeInventory setOverrideForItem:item value:sw.isOn];
    NSIndexPath *ip = [NSIndexPath indexPathForRow:sw.tag inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    FBGRBoolRuntimeItem *item = self.visible[(NSUInteger)ip.row];
    [FBGRBoolRuntimeInventory clearOverrideForItem:item];
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}
@end
