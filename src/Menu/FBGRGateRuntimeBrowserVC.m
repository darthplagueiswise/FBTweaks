#import "FBGRGateRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"

@interface FBGRGateRuntimeBrowserVC ()
@property(nonatomic, strong) FBGRGateProvider *provider;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *allParams;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *visible;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) UISegmentedControl *filterSeg; // All | iOS | Overrides
@end

@implementation FBGRGateRuntimeBrowserVC

- (instancetype)initWithProvider:(FBGRGateProvider *)p {
    if (!(self = [super initWithStyle:UITableViewStylePlain])) return nil;
    _provider = p;
    self.title = p ? [NSString stringWithFormat:@"%@ · Runtime", p.title] : @"Todos os Params MC";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    FBGRApplyTable(self.tableView, self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;

    // Filter segmented control
    _filterSeg = [[UISegmentedControl alloc] initWithItems:@[@"Todos", @"iOS Bool", @"Overrides"]];
    _filterSeg.selectedSegmentIndex = 0;
    _filterSeg.backgroundColor = FBGRCell();
    [_filterSeg addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _filterSeg;

    // Search
    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchBar.placeholder = @"Buscar param ou grupo";
    _search.searchBar.barStyle = UIBarStyleBlack;
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [[FBGRMCCatalog shared] loadIfNeeded];
    [self rebuildParams];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [self rebuildParams]; [self.tableView reloadData];
}

- (void)filterChanged { [self rebuildParams]; [self.tableView reloadData]; }

- (void)rebuildParams {
    NSString *q = self.search.isActive ? self.search.searchBar.text : nil;
    FBGRMCCatalog *cat = [FBGRMCCatalog shared];

    NSArray<FBGRMCParam *> *base;
    NSInteger seg = _filterSeg ? _filterSeg.selectedSegmentIndex : 0;
    if (seg == 1)      base = [cat iOSBoolParams];
    else if (seg == 2) base = [self overriddenParams];
    else               base = [cat allParams];

    if (q.length > 0) {
        NSString *low = q.lowercaseString;
        base = [base filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
                return [p.fullKey.lowercaseString containsString:low];
            }]];
    }

    // If provider specified, filter to provider's slotIds + search
    if (self.provider && q.length == 0 && seg == 0) {
        NSMutableSet<NSNumber*> *pSlots = [NSMutableSet set];
        for (FBGRFeaturedFlag *f in self.provider.featured) [pSlots addObject:@(f.slotId)];
        // Show provider's group prefix
        NSString *group = self.provider.providerID;
        base = [base filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
                return [pSlots containsObject:@(p.slotId)]
                    || [p.group.lowercaseString containsString:group.lowercaseString];
            }]];
    }

    self.allParams = base;
    self.visible   = base;
}

- (NSArray<FBGRMCParam*>*)overriddenParams {
    FBGRMCCatalog *cat = [FBGRMCCatalog shared];
    NSArray<NSNumber*> *ids = FBGRGateAllOverrideSlotIds();
    NSMutableArray *r = [NSMutableArray array];
    for (NSNumber *n in ids) {
        FBGRMCParam *p = [cat paramForSlotId:[n unsignedLongLongValue]];
        if (p) [r addObject:p];
        else {
            // Unknown slotId — create a placeholder
            FBGRMCParam *ph = [FBGRMCParam new];
            ph.slotId = [n unsignedLongLongValue];
            ph.fullKey = [NSString stringWithFormat:@"(slotId %llu)", (unsigned long long)ph.slotId];
            ph.type = @"boolValue"; ph.group = @"unknown"; ph.paramName = @"?";
            [r addObject:ph];
        }
    }
    return r;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    [self rebuildParams]; [self.tableView reloadData];
}

// ── TableView ─────────────────────────────────────────────────────────────────
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)self.visible.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return [NSString stringWithFormat:@"%lu params  |  %lu com override",
            (unsigned long)self.visible.count,
            (unsigned long)FBGRGateAllOverrideSlotIds().count];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    FBGRMCParam *p = self.visible[(NSUInteger)ip.row];

    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"rt"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"rt"];

    FBGRApplyCell(c, (NSInteger)p.slotId % 8, nil);
    c.textLabel.text = [NSString stringWithFormat:@"[%llu] %@", (unsigned long long)p.slotId, p.paramName];
    c.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];

    NSString *type = p.type.length > 5 ? [p.type substringToIndex:5] : p.type;
    BOOL isOverridden = FBGRGateIsSet(p.slotId);
    NSString *overrideMark = isOverridden
        ? [NSString stringWithFormat:@" → FORÇADO=%@", FBGRGateGet(p.slotId) ? @"YES" : @"NO"]
        : @"";
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · def=%@%@",
        p.group, type, p.defaultBool ? @"Y" : @"N", overrideMark];
    c.detailTextLabel.textColor = isOverridden ? FBGRAccent(2) : FBGRSub();

    c.selectionStyle = UITableViewCellSelectionStyleNone;

    if ([p.type isEqualToString:@"boolValue"]) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = isOverridden ? FBGRGateGet(p.slotId) : p.defaultBool;
        sw.tag = ip.row;
        sw.onTintColor = FBGRAccent((NSInteger)p.slotId % 8);
        [sw removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
        [sw addTarget:self action:@selector(swToggled:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
    } else {
        c.accessoryType = isOverridden ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        c.accessoryView = nil;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    FBGRMCParam *p = self.visible[(NSUInteger)ip.row];
    if ([p.type isEqualToString:@"boolValue"]) return; // handled by switch

    // For non-bool params: toggle override on/off
    if (FBGRGateIsSet(p.slotId)) FBGRGateClear(p.slotId);
    else FBGRGateSet(p.slotId, YES);
    [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)swToggled:(UISwitch *)sw {
    FBGRMCParam *p = self.visible[(NSUInteger)sw.tag];
    if (sw.isOn) FBGRGateSet(p.slotId, YES);
    else         FBGRGateClear(p.slotId);
    NSIndexPath *ip = [NSIndexPath indexPathForRow:sw.tag inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

@end
