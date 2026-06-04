#import "FBGRGateCategoryVC.h"
#import "FBGRMenuTheme.h"
#import "FBGRGateRuntimeBrowserVC.h"
#import "../Runtime/FBGRGateStore.h"
#import "../Runtime/FBGRMCCatalog.h"
#import "../FBGramPrefix.h"

extern void FBGRMCGateCacheRefresh(void);
extern void FBGRMCGateHooksEnsureInstalled(void);
extern BOOL FBGRDogFoodIsEnabled(void);
extern void FBGRDogFoodSetEnabled(BOOL enabled);
extern BOOL FBGRDogFoodPresentNagSheet(void);
extern NSString *FBGRDogFoodDiagnostic(void);
extern void FBGRDogFoodApplyPersistentState(void);

typedef NS_ENUM(NSInteger, FBGRCatSection) {
    FBGRCatSectionFeatured = 0,
    FBGRCatSectionActions  = 1,
    FBGRCatSectionCount    = 2,
};

@interface FBGRGateCategoryVC ()
@property(nonatomic, strong) FBGRGateProvider *provider;
@end

@implementation FBGRGateCategoryVC

- (instancetype)initWithProvider:(FBGRGateProvider *)p {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _provider = p; self.title = p.title; return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    FBGRApplyTable(self.tableView, self);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Limpar" style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];
    FBGRGateStoreWarmup();
    [[FBGRMCCatalog shared] loadIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; FBGRGateStoreWarmup(); [self.tableView reloadData]; }

- (BOOL)isDogFoodProvider { return [self.provider.providerID isEqualToString:@"dogfood"]; }
- (BOOL)isLiquidGlassMaster:(FBGRFeaturedFlag *)f { return [self.provider.providerID isEqualToString:@"liquidglass"] && f.slotId == 0; }
- (BOOL)isDogFoodNative:(FBGRFeaturedFlag *)f { return [self isDogFoodProvider] && f.slotId == 0xDDF0; }
- (BOOL)canOverrideFlag:(FBGRFeaturedFlag *)f {
    if ([self isLiquidGlassMaster:f] || [self isDogFoodNative:f]) return YES;
    FBGRMCParam *p = [[FBGRMCCatalog shared] paramForSlotId:f.slotId];
    return p && [p.type isEqualToString:@"boolValue"] && p.slotId > 0;
}

- (void)clearAll {
    for (FBGRFeaturedFlag *f in self.provider.featured) {
        if ([self isDogFoodNative:f]) { FBGRDogFoodSetEnabled(NO); continue; }
        if ([self isLiquidGlassMaster:f]) { [FBGRPrefs() removeObjectForKey:kFBGRLiquidGlassMaster]; continue; }
        if (f.slotId > 0) FBGRGateClear(f.slotId);
    }
    [FBGRPrefs() synchronize];
    FBGRMCGateCacheRefresh();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return FBGRCatSectionCount; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == FBGRCatSectionFeatured) return (NSInteger)self.provider.featured.count;
    return [self isDogFoodProvider] ? 3 : 2;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return s == FBGRCatSectionFeatured ? @"Flags do catálogo" : @"Ações"; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s != FBGRCatSectionFeatured) return nil;
    NSUInteger set = 0, possible = 0;
    for (FBGRFeaturedFlag *f in self.provider.featured) {
        if (![self canOverrideFlag:f]) continue;
        possible++;
        if ([self isDogFoodNative:f]) { if (FBGRDogFoodIsEnabled()) set++; }
        else if ([self isLiquidGlassMaster:f]) { if (FBGRPref(kFBGRLiquidGlassMaster)) set++; }
        else if (f.slotId > 0 && FBGRGateIsSet(f.slotId)) set++;
    }
    return [NSString stringWithFormat:@"%lu/%lu override(s). Read-only escondido: non-bool/slot0 inválido não recebe switch.", (unsigned long)set, (unsigned long)possible];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == FBGRCatSectionFeatured) {
        FBGRFeaturedFlag *flag = self.provider.featured[(NSUInteger)ip.row];
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"feat"];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"feat"];
        FBGRApplyCell(c, ip.row, self.provider.accentColor);
        c.accessoryView = nil; c.accessoryType = UITableViewCellAccessoryNone;

        BOOL can = [self canOverrideFlag:flag];
        BOOL isOn = NO;
        if ([self isDogFoodNative:flag]) isOn = FBGRDogFoodIsEnabled();
        else if ([self isLiquidGlassMaster:flag]) isOn = FBGRPref(kFBGRLiquidGlassMaster);
        else if (flag.slotId > 0) isOn = FBGRGateIsSet(flag.slotId) ? FBGRGateGet(flag.slotId) : ([[FBGRMCCatalog shared] paramForSlotId:flag.slotId].defaultBool);

        c.textLabel.text = flag.title;
        FBGRMCParam *param = flag.slotId > 0 ? [[FBGRMCCatalog shared] paramForSlotId:flag.slotId] : nil;
        NSString *detail = flag.detail ?: @"";
        if ([self isDogFoodNative:flag]) detail = [detail stringByAppendingFormat:@" → %@", FBGRDogFoodIsEnabled() ? @"ON" : @"OFF"];
        else if (param && FBGRGateIsSet(flag.slotId)) detail = [detail stringByAppendingFormat:@" → FORÇADO %@", FBGRGateGet(flag.slotId) ? @"YES" : @"NO"];
        else if (param) detail = [detail stringByAppendingFormat:@" · default=%@", param.defaultBool ? @"YES" : @"NO"];
        else if (!can) detail = [detail stringByAppendingString:@" · read-only"];
        c.detailTextLabel.text = detail;
        c.detailTextLabel.textColor = can ? FBGRSub() : UIColor.secondaryLabelColor;

        if (can) {
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = isOn; sw.tag = (NSInteger)ip.row; sw.onTintColor = FBGRAccentForProvider(self.provider.accentColor);
            [sw removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
            [sw addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
            c.accessoryType = UITableViewCellAccessoryDetailButton;
        }
        return c;
    }

    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"act"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"act"];
    FBGRApplyCell(c, ip.section * 10 + ip.row, nil);
    c.accessoryType  = UITableViewCellAccessoryDisclosureIndicator;
    if ([self isDogFoodProvider] && ip.row == 0) {
        c.textLabel.text = @"Abrir nag nativo DogFood/Gold";
        c.detailTextLabel.text = @"FBDogFoodUI.DogFoodController";
        c.imageView.image = FBGRSymbol(@"ladybug.fill", UIColor.systemOrangeColor);
    } else if (ip.row == ([self isDogFoodProvider] ? 1 : 0)) {
        c.textLabel.text  = @"Runtime Avançado desta categoria";
        c.detailTextLabel.text = @"Filtro por group/keywords reais do catálogo";
        c.imageView.image = FBGRSymbol(@"cpu", FBGRAccentForProvider(self.provider.accentColor));
    } else {
        c.textLabel.text  = @"Resetar overrides desta categoria";
        c.detailTextLabel.text = @"Remove somente flags listadas aqui";
        c.textLabel.textColor = UIColor.systemRedColor;
        c.imageView.image = FBGRSymbol(@"trash", UIColor.systemRedColor);
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == FBGRCatSectionFeatured) {
        FBGRFeaturedFlag *flag = self.provider.featured[(NSUInteger)ip.row];
        if (![self canOverrideFlag:flag]) {
            NSString *msg = [NSString stringWithFormat:@"%@\nslot=%llu\nNão recebe switch porque não é bool seguro ou é slotId 0 ambíguo.", flag.title, (unsigned long long)flag.slotId];
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Read-only" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
        return;
    }
    if ([self isDogFoodProvider] && ip.row == 0) {
        if (!FBGRDogFoodPresentNagSheet()) {
            NSString *diag = FBGRDogFoodDiagnostic() ?: @"n/a";
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"DogFood" message:diag preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"Copiar" style:UIAlertActionStyleDefault handler:^(__unused id x){ UIPasteboard.generalPasteboard.string = diag; }]];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
        return;
    }
    NSInteger runtimeRow = [self isDogFoodProvider] ? 1 : 0;
    if (ip.row == runtimeRow) [self.navigationController pushViewController:[[FBGRGateRuntimeBrowserVC alloc] initWithProvider:self.provider] animated:YES];
    else [self clearAll];
}

- (void)switchToggled:(UISwitch *)sw {
    FBGRFeaturedFlag *flag = self.provider.featured[(NSUInteger)sw.tag];
    if ([self isDogFoodNative:flag]) {
        FBGRDogFoodSetEnabled(sw.isOn);
        if (sw.isOn) FBGRDogFoodApplyPersistentState();
    } else if ([self isLiquidGlassMaster:flag]) {
        [FBGRPrefs() setBool:sw.isOn forKey:kFBGRLiquidGlassMaster];
        [FBGRPrefs() synchronize];
    } else if (flag.slotId > 0) {
        FBGRGateSet(flag.slotId, sw.isOn);
    }
    FBGRMCGateHooksEnsureInstalled();
    FBGRMCGateCacheRefresh();
    NSIndexPath *ip = [NSIndexPath indexPathForRow:sw.tag inSection:FBGRCatSectionFeatured];
    [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

@end
