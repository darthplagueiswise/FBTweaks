#import "FBGRGateCategoryVC.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Hooks/FBGRHookExports.h"

@interface FBGRGateCategoryVC ()
@property(nonatomic, assign) FBGRFeatureCategory category;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *items;
@end

@implementation FBGRGateCategoryVC
- (instancetype)initWithCategory:(FBGRFeatureCategory)category {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _category = category;
    self.title = FBGRFeatureCategoryTitle(category);
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    FBGRApplyGlassController(self);
    FBGRApplyGlassTable(self.tableView);
    self.items = [[FBGRMCCatalog shared] paramsForCategory:self.category];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Limpar" style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    FBGRGateWarmCacheFromPrefs();
    [self.tableView reloadData];
}

- (void)clear {
    for (FBGRMCParam *p in self.items) FBGRGateClear(p.slotId);
    FBGRMCGateCacheRefresh();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.items.count; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    NSUInteger forced = 0;
    for (FBGRMCParam *p in self.items) if (FBGRGateIsSet(p.slotId)) forced++;
    return [NSString stringWithFormat:@"%lu/%lu override(s). Nome completo quebrando linha; switch ON=Force YES, OFF=Force NO.", (unsigned long)forced, (unsigned long)self.items.count];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"flag"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"flag"];

    FBGRMCParam *p = self.items[(NSUInteger)ip.row];
    BOOL set = FBGRGateIsSet(p.slotId);
    BOOL val = set ? FBGRGateGet(p.slotId) : p.defaultBool;

    UISwitch *sw = [UISwitch new];
    sw.on = val;
    sw.tag = ip.row;
    sw.onTintColor = FBGRAccentColor();
    [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];

    NSString *subtitle = [NSString stringWithFormat:@"slot=%llu · default=%@%@",
                          (unsigned long long)p.slotId,
                          p.defaultBool ? @"YES" : @"NO",
                          set ? [NSString stringWithFormat:@" → FORÇADO %@", val ? @"YES" : @"NO"] : @""];
    FBGRConfigureSwitchCell(c, p.fullKey, subtitle, sw, FBGRSymbol(FBGRFeatureCategoryIcon(p.category), FBGRAccentColor()));
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

- (void)toggle:(UISwitch *)sw {
    FBGRMCParam *p = self.items[(NSUInteger)sw.tag];
    FBGRGateSet(p.slotId, sw.isOn);
    FBGRMCGateHooksEnsureInstalled();
    NSIndexPath *ip = [NSIndexPath indexPathForRow:sw.tag inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

@end
