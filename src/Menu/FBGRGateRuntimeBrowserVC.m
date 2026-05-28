#import "FBGRGateRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"

extern void FBGRMCGateCacheRefresh(void);
extern void FBGRMCGateHooksEnsureInstalled(void);

@interface FBGRGateRuntimeBrowserVC ()
@property(nonatomic, strong) FBGRGateProvider *provider;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *allParams;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *visible;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) UISegmentedControl *filterSeg; // Todos | Bool | iOS | Overrides
@end

@implementation FBGRGateRuntimeBrowserVC

- (instancetype)initWithProvider:(FBGRGateProvider *)p {
    if (!(self = [super initWithStyle:UITableViewStylePlain])) return nil;
    _provider = p;
    self.title = p ? [NSString stringWithFormat:@"%@ · Runtime", p.title] : @"Runtime MC";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    FBGRApplyTable(self.tableView, self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;

    _filterSeg = [[UISegmentedControl alloc] initWithItems:@[@"Todos", @"Bool", @"iOS", @"Overrides"]];
    _filterSeg.selectedSegmentIndex = 0;
    _filterSeg.backgroundColor = FBGRCell();
    [_filterSeg addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _filterSeg;

    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchBar.placeholder = @"Buscar param ou grupo";
    _search.searchBar.barStyle = UIBarStyleBlack;
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    FBGRGateStoreWarmup();
    [[FBGRMCCatalog shared] loadIfNeeded];
    [self rebuildParams];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    FBGRGateStoreWarmup();
    [self rebuildParams];
    [self.tableView reloadData];
}

- (void)filterChanged { [self rebuildParams]; [self.tableView reloadData]; }

- (BOOL)canOverrideParam:(FBGRMCParam *)p {
    return [p.type isEqualToString:@"boolValue"] && p.slotId > 0;
}

- (void)rebuildParams {
    NSString *q = self.search.isActive ? self.search.searchBar.text : nil;
    FBGRMCCatalog *cat = [FBGRMCCatalog shared];

    NSArray<FBGRMCParam *> *base;
    NSInteger seg = _filterSeg ? _filterSeg.selectedSegmentIndex : 0;
    if (seg == 1)      base = [cat safeBoolParams];
    else if (seg == 2) base = [[cat iOSBoolParams] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) { return p.slotId > 0; }]];
    else if (seg == 3) base = [self overriddenParams];
    else               base = [cat allParams];

    if (q.length > 0) {
        NSString *low = q.lowercaseString;
        base = [base filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
                return [p.fullKey.lowercaseString containsString:low]
                    || [[NSString stringWithFormat:@"%llu", (unsigned long long)p.slotId] containsString:low]
                    || [[NSString stringWithFormat:@"%llu", (unsigned long long)p.configKey] containsString:low];
            }]];
    }

    if (self.provider && q.length == 0 && seg == 0) {
        NSMutableSet<NSNumber*> *pSlots = [NSMutableSet set];
        for (FBGRFeaturedFlag *f in self.provider.featured) if (f.slotId > 0) [pSlots addObject:@(f.slotId)];
        NSString *group = self.provider.providerID ?: @"";
        base = [base filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
                return [pSlots containsObject:@(p.slotId)]
                    || [p.group.lowercaseString containsString:group.lowercaseString]
                    || [p.fullKey.lowercaseString containsString:group.lowercaseString];
            }]];
    }

    self.allParams = base ?: @[];
    self.visible   = base ?: @[];
}

- (NSArray<FBGRMCParam*>*)overriddenParams {
    FBGRMCCatalog *cat = [FBGRMCCatalog shared];
    NSArray<NSNumber*> *ids = FBGRGateAllOverrideSlotIds();
    NSMutableArray *r = [NSMutableArray array];
    for (NSNumber *n in ids) {
        uint64_t slot = [n unsignedLongLongValue];
        if (slot == 0) continue;
        FBGRMCParam *p = [cat paramForSlotId:slot];
        if (p) [r addObject:p];
        else {
            FBGRMCParam *ph = [FBGRMCParam new];
            ph.slotId = slot;
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

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)self.visible.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    FBGRMCCatalog *cat = [FBGRMCCatalog shared];
    return [NSString stringWithFormat:@"%lu visíveis | total=%lu | bool seguros=%lu | iOS=%lu | overrides=%lu | slot0/não-bool=read-only | %@",
            (unsigned long)self.visible.count,
            (unsigned long)cat.totalCount,
            (unsigned long)cat.safeBoolCount,
            (unsigned long)cat.iOSBoolCount,
            (unsigned long)FBGRGateAllOverrideSlotIds().count,
            cat.catalogSource ?: @"sem fonte"];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    FBGRMCParam *p = self.visible[(NSUInteger)ip.row];
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"rt"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"rt"];

    BOOL canOverride = [self canOverrideParam:p];
    BOOL isOverridden = canOverride && FBGRGateIsSet(p.slotId);

    FBGRApplyCell(c, (NSInteger)p.slotId % 8, nil);
    c.textLabel.text = [NSString stringWithFormat:@"[%llu] %@", (unsigned long long)p.slotId, p.paramName ?: @"?"];
    c.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];

    NSString *type = p.type.length > 5 ? [p.type substringToIndex:5] : (p.type ?: @"?");
    NSString *overrideMark = isOverridden
        ? [NSString stringWithFormat:@" → FORÇADO=%@", FBGRGateGet(p.slotId) ? @"YES" : @"NO"]
        : @"";
    NSString *ro = canOverride ? @"" : (p.slotId == 0 ? @" · read-only: slotId 0 ambíguo" : @" · read-only: não bool");
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · def=%@%@%@",
        p.group ?: @"?", type, p.defaultBool ? @"Y" : @"N", overrideMark, ro];
    c.detailTextLabel.textColor = isOverridden ? FBGRAccent(2) : (canOverride ? FBGRSub() : UIColor.secondaryLabelColor);

    c.selectionStyle = canOverride ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;

    if (canOverride) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = isOverridden ? FBGRGateGet(p.slotId) : p.defaultBool;
        sw.tag = ip.row;
        sw.onTintColor = FBGRAccent((NSInteger)p.slotId % 8);
        [sw removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
        [sw addTarget:self action:@selector(swToggled:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        c.accessoryType = UITableViewCellAccessoryNone;
    } else {
        c.accessoryView = nil;
        c.accessoryType = UITableViewCellAccessoryDetailButton;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    FBGRMCParam *p = self.visible[(NSUInteger)ip.row];
    if ([self canOverrideParam:p]) return;

    NSString *msg = [NSString stringWithFormat:@"%@\nslotId=%llu\ntype=%@\nconfigKey=%llu\nparamKey=%llu\n\nEste item não recebe switch porque o hook runtime só recebe slotId bool seguro. slotId 0 e params não-bool ficam somente leitura.",
                     p.fullKey ?: @"?", (unsigned long long)p.slotId, p.type ?: @"?",
                     (unsigned long long)p.configKey, (unsigned long long)p.paramKey];
    UIPasteboard.generalPasteboard.string = msg;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Param read-only" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)swToggled:(UISwitch *)sw {
    if ((NSUInteger)sw.tag >= self.visible.count) return;
    FBGRMCParam *p = self.visible[(NSUInteger)sw.tag];
    if (![self canOverrideParam:p]) { sw.on = p.defaultBool; return; }
    FBGRGateSet(p.slotId, sw.isOn);
    FBGRMCGateHooksEnsureInstalled();
    FBGRMCGateCacheRefresh();
    NSIndexPath *ip = [NSIndexPath indexPathForRow:sw.tag inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

@end
