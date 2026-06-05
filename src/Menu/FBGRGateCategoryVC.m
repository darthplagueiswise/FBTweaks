#import "FBGRGateCategoryVC.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../Runtime/FBGRGateStore.h"

extern void FBGRMCGateHooksEnsureInstalled(void);
extern void FBGRMCGateCacheRefresh(void);

@interface FBGRGateCategoryVC ()
@property(nonatomic, assign) FBGRFeatureCategory category;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *items;
@end

@implementation FBGRGateCategoryVC
- (instancetype)initWithCategory:(FBGRFeatureCategory)category {
    if (!(self=[super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _category=category; self.title=FBGRFeatureCategoryTitle(category); return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    FBGRApplyGlassController(self); FBGRApplyGlassTable(self.tableView);
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 96.0;
    self.items=[[FBGRMCCatalog shared] paramsForCategory:self.category];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Limpar" style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; FBGRGateWarmCacheFromPrefs(); [self.tableView reloadData]; }
- (void)clear { for (FBGRMCParam *p in self.items) FBGRGateClear(p.slotId); FBGRMCGateCacheRefresh(); [self.tableView reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section { return [NSString stringWithFormat:@"%lu flags BOOL reais. Toggle liga/desliga e instala hooks MC imediatamente.", (unsigned long)self.items.count]; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"flag"]; if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"flag"];
    FBGRMCParam *p=self.items[ip.row];
    BOOL set=FBGRGateIsSet(p.slotId); BOOL val=set?FBGRGateGet(p.slotId):p.defaultBool;
    NSString *detail=[NSString stringWithFormat:@"slot=%llu · default=%@%@", (unsigned long long)p.slotId, p.defaultBool?@"YES":@"NO", set?[NSString stringWithFormat:@" → FORÇADO %@", val?@"YES":@"NO"]:@""];
    FBGRApplyReadableTextCell(c, p.fullKey, detail);
    UISwitch *sw=[UISwitch new]; sw.on=val; sw.tag=ip.row; sw.onTintColor=FBGRAccentColor(); [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=sw; c.selectionStyle=UITableViewCellSelectionStyleNone; return c;
}
- (void)toggle:(UISwitch *)sw { FBGRMCParam *p=self.items[sw.tag]; FBGRGateSet(p.slotId, sw.isOn); FBGRMCGateHooksEnsureInstalled(); FBGRMCGateCacheRefresh(); NSIndexPath *ip=[NSIndexPath indexPathForRow:sw.tag inSection:0]; [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone]; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip { [tv deselectRowAtIndexPath:ip animated:YES]; }
@end
