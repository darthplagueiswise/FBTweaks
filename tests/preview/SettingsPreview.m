#import <UIKit/UIKit.h>
#import "FBTUIKit26LiquidGlass.h"
#import "FBTSettingsCatalog.h"
#import "FBTSettingsPresentation.h"
#import "FBTDefaults.h"

NSString * const FBTMCNativeProbeTigonKey = @"fbt_mc_native_tigon_probe_session";
NSString * const FBTMCNativeProbeFetcherKey = @"fbt_mc_native_fetcher_probe_session";

// A real UIKit host for the production helpers; never a mock of their rendering.
@interface FBTStylePreviewController : UITableViewController
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
- (instancetype)initWithCategory:(NSString *)category;
@end
@implementation FBTStylePreviewController
- (instancetype)initWithCategory:(NSString *)category {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) _category = [category copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FBTweak";
    for (NSDictionary *category in [FBTSettingsCatalog categories]) {
        if ([category[@"id"] isEqual:self.category]) self.title = category[@"title"];
    }
    self.sections = [FBTSettingsCatalog sectionsForCategory:self.category query:nil];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:nil action:nil];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    FBTUIKit26ConfigureViewController(self);
    FBTUIKit26ConfigureTableView(self.tableView);
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchBar.placeholder = @"Buscar ajustes e ferramentas";
    self.navigationItem.searchController = search;
    FBTUIKit26ConfigureSearchNavigationItem(self.navigationItem);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return FBTSettingsFooter(self.sections[section]); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSString *key=row[@"key"];
    FBTConfigureSettingsMenuCell(cell,row,key ? [NSUserDefaults.standardUserDefaults boolForKey:key] : NO,
        self,@selector(toggleChanged:));
    return cell;
}
- (void)toggleChanged:(FBTSettingsSwitch *)toggle { [FBTDefaults setBool:toggle.on forKey:toggle.prefKey]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    for (NSDictionary *category in [FBTSettingsCatalog categories]) {
        if ([row[@"dest"] isEqual:[@"category:" stringByAppendingString:category[@"id"]]] || [row[@"category"] isEqual:category[@"id"]]) {
            [self.navigationController pushViewController:[[FBTStylePreviewController alloc] initWithCategory:category[@"id"]] animated:YES];
            return;
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}
@end

@interface FBTStylePreviewDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation FBTStylePreviewDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [FBTDefaults registerDefaultsOnce];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    NSString *category = NSProcessInfo.processInfo.environment[@"FBT_PREVIEW_CATEGORY"];
    FBTStylePreviewController *root = [[FBTStylePreviewController alloc] initWithCategory:nil];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    self.window.rootViewController = navigation;
    FBTStylePreviewController *controller = root;
    if (category.length) {
        controller = [[FBTStylePreviewController alloc] initWithCategory:category];
        [navigation pushViewController:controller animated:NO];
    }
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSMutableArray *failures = [NSMutableArray array];
        if (controller.navigationItem.titleView) [failures addObject:@"Native navigation title replaced"];
        UITableViewCell *cell = [controller.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        if (!controller.sections.count) [failures addObject:@"Production settings catalog is empty"];
        UIListContentConfiguration *content = [cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class] ? (UIListContentConfiguration *)cell.contentConfiguration : nil;
        if (!cell || !content.textProperties.adjustsFontForContentSizeCategory || content.secondaryTextProperties.numberOfLines != 0) [failures addObject:@"Settings text does not support Dynamic Type"];
        UIVisualEffect *effect = FBTUIKit26GlassEffect(NO, YES, UIColor.systemBlueColor);
        NSString *variant = NSProcessInfo.processInfo.environment[@"FBT_PREVIEW_VARIANT"] ?: @"light";
        BOOL requestedReduceTransparency = [variant isEqual:@"reduce-transparency"];
        BOOL requestedIncreasedContrast = [variant isEqual:@"high-contrast"];
        BOOL reduceTransparency = UIAccessibilityIsReduceTransparencyEnabled();
        BOOL increasedContrast = UIAccessibilityDarkerSystemColorsEnabled();
        // Verify the requested system state before evaluating its fallback.
        // An ignored Simulator preference must fail, never silently skip coverage.
        if (reduceTransparency != requestedReduceTransparency) [failures addObject:@"Simulator Reduce Transparency state differs from requested variant"];
        if (increasedContrast != requestedIncreasedContrast) [failures addObject:@"Simulator Increase Contrast state differs from requested variant"];
        BOOL opaque = reduceTransparency || increasedContrast;
        if (opaque && effect) [failures addObject:@"Accessibility opaque fallback ignored"];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
        if (@available(iOS 26.0, *)) {
            if (!opaque && ![effect isKindOfClass:UIGlassEffect.class]) [failures addObject:@"iOS 26 is not using UIGlassEffect"];
            if (!opaque && ![(UIGlassEffect *)effect isInteractive]) [failures addObject:@"Glass interactive property missing"];
            UIVisualEffect *container = FBTUIKit26GlassContainerEffect(12.0);
            if (!opaque && ![container isKindOfClass:UIGlassContainerEffect.class]) [failures addObject:@"Glass container API failed"];
        }
#endif
        FBTUIKit26GlassPanelView *panel = [[FBTUIKit26GlassPanelView alloc] initWithRadius:20];
        if (panel.effect && ![panel.contentView.backgroundColor isEqual:UIColor.clearColor]) [failures addObject:@"Glass has an extra opaque content layer"];
        UIColor *panelFill = [panel.contentView.backgroundColor resolvedColorWithTraitCollection:controller.traitCollection];
        BOOL panelIsOpaque = panel.effect == nil && CGColorGetAlpha(panelFill.CGColor) >= 0.999;
        if (opaque && !panelIsOpaque) [failures addObject:@"Accessibility panel fallback is not an opaque semantic surface"];
        NSDictionary *result = @{ @"failures": failures, @"category": category.length ? category : @"root", @"systemVersion": UIDevice.currentDevice.systemVersion, @"accessibilityVariant": variant, @"requestedReduceTransparency": @(requestedReduceTransparency), @"requestedIncreasedContrast": @(requestedIncreasedContrast), @"reduceTransparency": @(reduceTransparency), @"increasedContrast": @(increasedContrast), @"traitContrastHigh": @(controller.traitCollection.accessibilityContrast == UIAccessibilityContrastHigh), @"panelIsOpaque": @(panelIsOpaque) };
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [data writeToURL:[documents URLByAppendingPathComponent:@"style-result.json"] atomically:YES];
    });
    return YES;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(FBTStylePreviewDelegate.class)); }
}
