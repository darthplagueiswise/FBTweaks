// A standalone, real-UIKit Simulator app. No Facebook, hooks, UIKit doubles, or network.
// Built by scripts/test-uikit-simulator.py together with the production glass helper.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "FBTUIKit26LiquidGlass.h"

#ifndef FBT_UIKIT_HAS_OVERVIEW_HEADER
#error The runner must explicitly detect the overview-header API in the selected helper.
#endif
#ifndef FBT_UIKIT_BASELINE_MODE
#define FBT_UIKIT_BASELINE_MODE 0
#endif
#if !FBT_UIKIT_HAS_OVERVIEW_HEADER && !FBT_UIKIT_BASELINE_MODE
#error A fixed run must exercise the real overview header.
#endif

static id FBTValue(id value) { return value ?: NSNull.null; }

static NSArray<NSNumber *> *FBTColor(UIColor *color) {
    if (!color) return @[];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    UIColor *resolved = [color resolvedColorWithTraitCollection:UITraitCollection.currentTraitCollection];
    if (![resolved getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [resolved getWhite:&white alpha:&a];
        r = g = b = white;
    }
    return @[@(r), @(g), @(b), @(a)];
}

// Snapshot public values, rather than comparing appearance object identity (setters copy).
static NSDictionary *FBTAppearance(UIBarAppearance *appearance) {
    if (!appearance) return @{};
    NSMutableDictionary *values = [@{
        @"background": FBTColor(appearance.backgroundColor),
        @"effect": appearance.backgroundEffect ? NSStringFromClass(appearance.backgroundEffect.class) : @"",
        @"backgroundImage": FBTValue(appearance.backgroundImage),
        @"imageMode": @(appearance.backgroundImageContentMode),
        @"shadow": FBTColor(appearance.shadowColor),
        @"shadowImage": FBTValue(appearance.shadowImage),
        @"idiom": @(appearance.idiom)
    } mutableCopy];
    if ([appearance isKindOfClass:UINavigationBarAppearance.class]) {
        UINavigationBarAppearance *nav = (UINavigationBarAppearance *)appearance;
        values[@"title"] = [nav.titleTextAttributes copy];
        values[@"largeTitle"] = [nav.largeTitleTextAttributes copy];
        values[@"button"] = [nav.buttonAppearance.normal.titleTextAttributes copy];
        values[@"backButton"] = [nav.backButtonAppearance.normal.titleTextAttributes copy];
        values[@"doneButton"] = [nav.doneButtonAppearance.normal.titleTextAttributes copy];
    }
    return values;
}

static NSDictionary *FBTSharedChrome(UINavigationController *nav, UITabBarController *tabs) {
    UINavigationBar *bar = nav.navigationBar;
    UIToolbar *toolbar = nav.toolbar;
    UITabBar *tab = tabs.tabBar;
    return @{
        @"nav.standard": FBTAppearance(bar.standardAppearance),
        @"nav.scrollEdge": FBTAppearance(bar.scrollEdgeAppearance),
        @"nav.compact": FBTAppearance(bar.compactAppearance),
        @"nav.compactScrollEdge": FBTAppearance(bar.compactScrollEdgeAppearance),
        @"nav.translucent": @(bar.translucent), @"nav.largeTitles": @(bar.prefersLargeTitles),
        @"nav.background": FBTColor(bar.backgroundColor), @"nav.tint": FBTColor(bar.tintColor),
        @"nav.barTint": FBTColor(bar.barTintColor), @"nav.style": @(bar.barStyle),
        @"nav.titleAttributes": [bar.titleTextAttributes copy] ?: @{},
        @"nav.largeTitleAttributes": [bar.largeTitleTextAttributes copy] ?: @{},
        @"toolbar.standard": FBTAppearance(toolbar.standardAppearance),
        @"toolbar.scrollEdge": FBTAppearance(toolbar.scrollEdgeAppearance),
        @"toolbar.compact": FBTAppearance(toolbar.compactAppearance),
        @"toolbar.compactScrollEdge": FBTAppearance(toolbar.compactScrollEdgeAppearance),
        @"toolbar.translucent": @(toolbar.translucent), @"toolbar.background": FBTColor(toolbar.backgroundColor),
        @"toolbar.tint": FBTColor(toolbar.tintColor), @"toolbar.barTint": FBTColor(toolbar.barTintColor),
        @"toolbar.style": @(toolbar.barStyle),
        @"tab.standard": FBTAppearance(tab.standardAppearance),
        @"tab.scrollEdge": FBTAppearance(tab.scrollEdgeAppearance),
        @"tab.translucent": @(tab.translucent), @"tab.background": FBTColor(tab.backgroundColor),
        @"tab.tint": FBTColor(tab.tintColor), @"tab.barTint": FBTColor(tab.barTintColor),
        @"tab.style": @(tab.barStyle)
    };
}

static NSArray<NSString *> *FBTDifferences(NSDictionary *before, NSDictionary *after) {
    NSMutableArray *keys = [NSMutableArray new];
    for (NSString *key in before) if (![before[key] isEqual:after[key]]) [keys addObject:key];
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}

static void FBTSeedChrome(UINavigationController *nav, UITabBarController *tabs) {
    NSArray<UIColor *> *colors = @[
        [UIColor colorWithRed:0.17 green:0.23 blue:0.37 alpha:1],
        [UIColor colorWithRed:0.29 green:0.19 blue:0.41 alpha:1],
        [UIColor colorWithRed:0.11 green:0.39 blue:0.31 alpha:1],
        [UIColor colorWithRed:0.43 green:0.25 blue:0.13 alpha:1]
    ];
    NSMutableArray *navAppearances = [NSMutableArray new];
    NSMutableArray *toolbarAppearances = [NSMutableArray new];
    for (NSUInteger i = 0; i < 4; i++) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = colors[i];
        appearance.shadowColor = UIColor.yellowColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.cyanColor,
            NSFontAttributeName: [UIFont systemFontOfSize:16 + i weight:UIFontWeightMedium]};
        appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.orangeColor};
        appearance.buttonAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.magentaColor};
        [navAppearances addObject:appearance];
        UIToolbarAppearance *tool = [UIToolbarAppearance new];
        [tool configureWithOpaqueBackground];
        tool.backgroundColor = colors[i];
        tool.shadowColor = UIColor.yellowColor;
        [toolbarAppearances addObject:tool];
    }
    UINavigationBar *bar = nav.navigationBar;
    bar.standardAppearance = navAppearances[0]; bar.scrollEdgeAppearance = navAppearances[1];
    bar.compactAppearance = navAppearances[2]; bar.compactScrollEdgeAppearance = navAppearances[3];
    bar.prefersLargeTitles = YES; bar.translucent = NO;
    bar.backgroundColor = UIColor.orangeColor; bar.barTintColor = UIColor.brownColor;
    bar.tintColor = UIColor.cyanColor;
    bar.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.greenColor};
    bar.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.yellowColor};
    UIToolbar *toolbar = nav.toolbar;
    toolbar.standardAppearance = toolbarAppearances[0]; toolbar.scrollEdgeAppearance = toolbarAppearances[1];
    toolbar.compactAppearance = toolbarAppearances[2]; toolbar.compactScrollEdgeAppearance = toolbarAppearances[3];
    toolbar.translucent = NO; toolbar.backgroundColor = UIColor.purpleColor;
    toolbar.barTintColor = UIColor.brownColor; toolbar.tintColor = UIColor.yellowColor;
    UITabBarAppearance *tab = [UITabBarAppearance new];
    [tab configureWithOpaqueBackground]; tab.backgroundColor = colors[0]; tab.shadowColor = UIColor.greenColor;
    UITabBarAppearance *edge = [tab copy]; edge.backgroundColor = colors[1];
    tabs.tabBar.standardAppearance = tab; tabs.tabBar.scrollEdgeAppearance = edge;
    tabs.tabBar.translucent = NO; tabs.tabBar.backgroundColor = UIColor.orangeColor;
    tabs.tabBar.barTintColor = UIColor.brownColor; tabs.tabBar.tintColor = UIColor.greenColor;
}

static UIImage *FBTImage(UIView *view) {
    [view layoutIfNeeded];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.whiteColor setFill]; UIRectFill(view.bounds);
        if (![view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES]) {
            [NSException raise:@"SnapshotFailure" format:@"UIKit could not draw %@", view];
        }
    }];
}

// Compare interior pixels of the rendered cell, avoiding table separators and rounded edges.
static double FBTPixelDifference(UIImage *first, UIImage *second) {
    CGImageRef a = first.CGImage, b = second.CGImage;
    size_t width = CGImageGetWidth(a), height = CGImageGetHeight(a);
    if (width != CGImageGetWidth(b) || height != CGImageGetHeight(b) || width < 48 || height < 24) {
        [NSException raise:@"SnapshotDimensions" format:@"Unexpected cell raster size"];
    }
    size_t bytes = width * height * 4;
    NSMutableData *dataA = [NSMutableData dataWithLength:bytes], *dataB = [NSMutableData dataWithLength:bytes];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctxA = CGBitmapContextCreate(dataA.mutableBytes, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextRef ctxB = CGBitmapContextCreate(dataB.mutableBytes, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctxA || !ctxB) [NSException raise:@"SnapshotAllocation" format:@"Cannot allocate raster contexts"];
    CGContextDrawImage(ctxA, CGRectMake(0, 0, width, height), a);
    CGContextDrawImage(ctxB, CGRectMake(0, 0, width, height), b);
    CGContextRelease(ctxA); CGContextRelease(ctxB);
    const unsigned char *pixelsA = dataA.bytes, *pixelsB = dataB.bytes;
    double total = 0; NSUInteger count = 0;
    for (size_t y = 8; y < height - 8; y++) {
        for (size_t x = 20; x < width - 20; x++) {
            for (size_t channel = 0; channel < 3; channel++) {
                size_t offset = (y * width + x) * 4 + channel;
                total += abs((int)pixelsA[offset] - (int)pixelsB[offset]); count++;
            }
        }
    }
    return total / (count * 255.0);
}

static void FBTCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) [labels addObject:(UILabel *)view];
    for (UIView *child in view.subviews) FBTCollectLabels(child, labels);
}

#if FBT_UIKIT_HAS_OVERVIEW_HEADER
static NSDictionary *FBTHeaderMeasurement(UITableView *table) {
    UIView *header = table.tableHeaderView;
    [table layoutIfNeeded]; [header layoutIfNeeded];
    NSMutableArray<UILabel *> *labels = [NSMutableArray new]; FBTCollectLabels(header, labels);
    NSMutableArray *measurements = [NSMutableArray new], *issues = [NSMutableArray new], *rects = [NSMutableArray new];
    if (!header || labels.count < 2) [issues addObject:@"Expected a real title and description label"];
    if (fabs(header.bounds.size.width - table.bounds.size.width) > 1) [issues addObject:@"Header did not follow table width"];
    CGSize fitted = [header systemLayoutSizeFittingSize:CGSizeMake(table.bounds.size.width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (!isfinite(header.bounds.size.height) || header.bounds.size.height < fitted.height - 1) {
        [issues addObject:@"Header frame is shorter than its Auto Layout fitting height"];
    }
    for (UILabel *label in labels) {
        CGRect rect = [label convertRect:label.bounds toView:header];
        NSAttributedString *text = label.attributedText ?: [[NSAttributedString alloc] initWithString:label.text
            attributes:@{NSFontAttributeName: label.font}];
        CGRect needed = [text boundingRectWithSize:CGSizeMake(MAX(1, label.bounds.size.width), CGFLOAT_MAX)
            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading context:nil];
        if (label.hidden || label.alpha < 0.01 || label.bounds.size.width < 1 || label.bounds.size.height < ceil(needed.size.height) - 1) {
            [issues addObject:@"A header label is hidden, empty-sized, or truncates its full text"];
        }
        if (!CGRectContainsRect(CGRectInset(header.bounds, -1, -1), rect)) [issues addObject:@"A label extends outside the table header"];
        if (!label.adjustsFontForContentSizeCategory) [issues addObject:@"A label does not opt into Dynamic Type"];
        for (NSValue *existing in rects) {
            CGRect overlap = CGRectIntersection(rect, existing.CGRectValue);
            if (!CGRectIsNull(overlap) && overlap.size.width > 1 && overlap.size.height > 1) [issues addObject:@"Header labels overlap"];
        }
        [rects addObject:[NSValue valueWithCGRect:rect]];
        [measurements addObject:@{@"text": label.text ?: @"", @"frame": NSStringFromCGRect(rect),
            @"font_size": @(label.font.pointSize), @"full_text_height": @(ceil(needed.size.height))}];
    }
    return @{@"issues": issues, @"labels": measurements, @"height": @(header.bounds.size.height),
        @"width": @(header.bounds.size.width), @"fitting_height": @(fitted.height),
        @"category": table.traitCollection.preferredContentSizeCategory};
}
#endif

@interface FBTRegressionRun : NSObject <UITableViewDataSource>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *cases;
@property(nonatomic, strong) UINavigationController *navigation;
@property(nonatomic, strong) UITabBarController *tabs;
@property(nonatomic, strong) UIViewController *host;
@property(nonatomic, strong) UIViewController *root;
@property(nonatomic, strong) UIViewController *child;
@property(nonatomic, strong) UIView *customTitle;
@property(nonatomic, strong) NSDictionary *originalChrome;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) UITableViewCell *cell;
@property(nonatomic, strong) UIImage *normalCell;
@property(nonatomic, strong) NSDictionary *normalHeader;
@property(nonatomic) BOOL finished;
- (void)start;
@end

@implementation FBTRegressionRun

- (NSURL *)documents {
    return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}

- (void)record:(NSString *)name pass:(BOOL)pass details:(NSDictionary *)details {
    [self.cases addObject:@{@"id": name, @"kind": @"behavior", @"status": pass ? @"pass" : @"fail", @"details": details ?: @{}}];
}

- (void)capture:(NSString *)name {
    if (![NSBundle.mainBundle.infoDictionary[@"FBTRegressionScreenshots"] boolValue]) return;
    NSData *png = UIImagePNGRepresentation(FBTImage(self.window));
    NSError *error = nil;
    if (![png writeToURL:[[self documents] URLByAppendingPathComponent:[name stringByAppendingString:@".png"]]
                 options:NSDataWritingAtomic error:&error]) {
        [NSException raise:@"ScreenshotWrite" format:@"%@", error];
    }
}

- (void)finish {
    if (self.finished) return;
    self.finished = YES;
    NSDictionary *result = @{@"schema_version": @1, @"completed": @YES,
        @"run_id": NSBundle.mainBundle.infoDictionary[@"FBTRegressionRunID"] ?: @"missing",
        @"source_ref": NSBundle.mainBundle.infoDictionary[@"FBTRegressionSourceRef"] ?: @"missing",
        @"baseline": @((BOOL)FBT_UIKIT_BASELINE_MODE), @"has_overview_header": @((BOOL)FBT_UIKIT_HAS_OVERVIEW_HEADER),
        @"os_version": UIDevice.currentDevice.systemVersion, @"cases": self.cases ?: @[]};
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!json || ![json writeToURL:[[self documents] URLByAppendingPathComponent:@"ui-regression.json"]
                          options:NSDataWritingAtomic error:&error]) NSLog(@"FBT UIKit result write failed: %@", error);
}

- (void)later:(dispatch_block_t)block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.finished) return;
        @try { block(); }
        @catch (NSException *error) {
            [self.cases addObject:@{@"id": @"infrastructure.exception", @"kind": @"infrastructure", @"status": @"error",
                @"details": @{@"name": error.name, @"reason": error.reason ?: @""}}];
            [self finish];
        }
    });
}

- (void)start {
    self.cases = [NSMutableArray new];
    [self.cases addObject:@{@"id": @"runtime.ios26", @"kind": @"infrastructure",
        @"status": FBTUIKit26IsAvailable() ? @"pass" : @"error", @"details": @{ @"version": UIDevice.currentDevice.systemVersion }}];
    if (!FBTUIKit26IsAvailable()) { [self finish]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.finished) return;
        [self.cases addObject:@{@"id": @"infrastructure.host_timeout", @"kind": @"infrastructure", @"status": @"error", @"details": @{}}];
        [self finish];
    });
    [self later:^{
        self.host = [UIViewController new]; self.host.title = @"Host application";
        self.host.view.backgroundColor = UIColor.systemBackgroundColor;
        self.navigation = [[UINavigationController alloc] initWithRootViewController:self.host];
        self.tabs = [UITabBarController new]; self.tabs.viewControllers = @[self.navigation];
        self.window.rootViewController = self.tabs;
        [self.navigation setToolbarHidden:NO animated:NO];
        self.root = [UIViewController new]; self.root.title = @"FBT Settings";
        self.root.view.backgroundColor = UIColor.systemBackgroundColor;
        [self.navigation pushViewController:self.root animated:NO];
        [self later:^{ [self testRoot]; }];
    }];
}

- (void)testRoot {
    FBTSeedChrome(self.navigation, self.tabs);
    self.originalChrome = FBTSharedChrome(self.navigation, self.tabs);
    FBTConfigureNavigationChromeForGlass(self.root);
    NSArray *changed = FBTDifferences(self.originalChrome, FBTSharedChrome(self.navigation, self.tabs));
    [self record:@"navigation.chrome.root" pass:changed.count == 0 details:@{@"changed_properties": changed}];
    [self record:@"navigation.title.root" pass:self.root.navigationItem.titleView == nil
        details:@{@"title_view_class": self.root.navigationItem.titleView ? NSStringFromClass(self.root.navigationItem.titleView.class) : @"nil"}];
    [self capture:@"navigation-root"];
    self.child = [UIViewController new]; self.child.title = @"Child settings";
    self.child.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *custom = [UILabel new]; custom.text = @"Host custom title"; [custom sizeToFit];
    self.customTitle = custom; self.child.navigationItem.titleView = custom;
    [self.navigation pushViewController:self.child animated:NO];
    [self later:^{ [self testChild]; }];
}

- (void)testChild {
    // Seed again so baseline's first mutation cannot mask a second invocation.
    FBTSeedChrome(self.navigation, self.tabs);
    NSDictionary *before = FBTSharedChrome(self.navigation, self.tabs);
    FBTConfigureNavigationChromeForGlass(self.child);
    NSArray *changed = FBTDifferences(before, FBTSharedChrome(self.navigation, self.tabs));
    [self record:@"navigation.chrome.child" pass:changed.count == 0 details:@{@"changed_properties": changed}];
    [self record:@"navigation.title.child" pass:self.child.navigationItem.titleView == self.customTitle
        details:@{@"preserved_custom_title": @(self.child.navigationItem.titleView == self.customTitle)}];
    [self capture:@"navigation-child"];
    [self.navigation popToRootViewControllerAnimated:NO];
    [self later:^{
        NSArray *changedOnReturn = FBTDifferences(self.originalChrome, FBTSharedChrome(self.navigation, self.tabs));
        [self record:@"navigation.host_return" pass:changedOnReturn.count == 0 && self.navigation.topViewController == self.host
            details:@{@"changed_properties": changedOnReturn}];
        [self prepareTable];
    }];
}

- (void)prepareTable {
    UIViewController *fixture = [UIViewController new]; fixture.view.backgroundColor = UIColor.whiteColor;
    self.window.rootViewController = fixture;
    self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 70, 280, 650) style:UITableViewStyleInsetGrouped];
    self.table.backgroundColor = UIColor.whiteColor; self.table.rowHeight = 72;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone; self.table.dataSource = self;
    self.table.traitOverrides.userInterfaceStyle = UIUserInterfaceStyleLight;
    self.table.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryLarge;
    [fixture.view addSubview:self.table]; [self.table reloadData];
    [self later:^{
        [self.table layoutIfNeeded];
        self.cell = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        if (!self.cell || !self.cell.window) [NSException raise:@"MissingVisibleCell" format:@"Fixture row did not become visible"];
        self.normalCell = FBTImage(self.cell);
        BOOL singleOwner = self.cell.backgroundConfiguration != nil && self.cell.backgroundView == nil && self.cell.selectedBackgroundView == nil;
        [self record:@"selection.configuration" pass:singleOwner && self.cell.selectionStyle != UITableViewCellSelectionStyleNone
            details:@{@"background_configuration": @(self.cell.backgroundConfiguration != nil),
                @"legacy_background_view": @(self.cell.backgroundView != nil), @"legacy_selected_background_view": @(self.cell.selectedBackgroundView != nil),
                @"selection_style": @(self.cell.selectionStyle)}];
        [self capture:@"selection-normal"];
        [self.cell setHighlighted:YES animated:NO];
        [self later:^{ [self testHighlight]; }];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Intentionally empty content: only the helper's background can change these pixels.
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    FBTUIKit26ConfigureTableCell(cell);
    return cell;
}

- (void)testHighlight {
    double difference = FBTPixelDifference(self.normalCell, FBTImage(self.cell));
    [self record:@"selection.highlight_feedback" pass:self.cell.highlighted && difference > 0.005
        details:@{@"mean_rgb_difference": @(difference), @"highlighted": @(self.cell.highlighted)}];
    [self capture:@"selection-highlighted"];
    [self.cell setHighlighted:NO animated:NO];
    [self.table selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
    [self later:^{
        double selectedDifference = FBTPixelDifference(self.normalCell, FBTImage(self.cell));
        [self record:@"selection.selected_feedback" pass:self.cell.selected && selectedDifference > 0.005
            details:@{@"mean_rgb_difference": @(selectedDifference), @"selected": @(self.cell.selected)}];
        [self capture:@"selection-selected"];
        [self.table deselectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO];
        [self later:^{
            double restoredDifference = FBTPixelDifference(self.normalCell, FBTImage(self.cell));
            [self record:@"selection.restores" pass:!self.cell.selected && !self.cell.highlighted && restoredDifference < 0.005
                details:@{@"mean_rgb_difference": @(restoredDifference)}];
            [self prepareHeader];
        }];
    }];
}

- (void)prepareHeader {
#if FBT_UIKIT_HAS_OVERVIEW_HEADER
    [self.table.traitCollection performAsCurrentTraitCollection:^{
        self.table.tableHeaderView = FBTUIKit26CreateOverviewHeader(self.table.bounds.size.width);
        FBTUIKit26UpdateTableHeaderLayout(self.table);
    }];
    [self later:^{
        FBTUIKit26UpdateTableHeaderLayout(self.table);
        self.normalHeader = FBTHeaderMeasurement(self.table);
        [self record:@"header.narrow" pass:[self.normalHeader[@"issues"] count] == 0 details:self.normalHeader];
        [self capture:@"header-narrow"];
        // Update the SAME header in the live hierarchy; recreating it would hide trait-update bugs.
        self.table.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
        [self later:^{ [self testAccessibleHeader]; }];
    }];
#else
    for (NSString *name in @[@"header.narrow", @"header.accessibility", @"header.resize"]) {
        [self.cases addObject:@{@"id": name, @"kind": @"behavior", @"status": @"skipped",
            @"details": @{@"reason": @"Selected baseline predates the overview-header API"}}];
    }
    [self finish];
#endif
}

- (void)testAccessibleHeader {
#if FBT_UIKIT_HAS_OVERVIEW_HEADER
    FBTUIKit26UpdateTableHeaderLayout(self.table);
    NSDictionary *accessible = FBTHeaderMeasurement(self.table);
    BOOL fontsGrew = [accessible[@"labels"] count] == [self.normalHeader[@"labels"] count] && [accessible[@"labels"] count] >= 2;
    for (NSUInteger i = 0; fontsGrew && i < [accessible[@"labels"] count]; i++) {
        fontsGrew = [accessible[@"labels"][i][@"font_size"] doubleValue] > [self.normalHeader[@"labels"][i][@"font_size"] doubleValue] + 1;
    }
    BOOL pass = [accessible[@"issues"] count] == 0 && fontsGrew &&
        [accessible[@"category"] isEqual:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge] &&
        [accessible[@"height"] doubleValue] > [self.normalHeader[@"height"] doubleValue] + 1;
    NSMutableDictionary *details = [accessible mutableCopy]; details[@"fonts_grew"] = @(fontsGrew);
    details[@"normal_height"] = self.normalHeader[@"height"];
    [self record:@"header.accessibility" pass:pass details:details];
    [self capture:@"header-accessibility"];
    CGRect frame = self.table.frame; frame.size.width = 360; self.table.frame = frame;
    [self later:^{
        FBTUIKit26UpdateTableHeaderLayout(self.table);
        NSDictionary *wide = FBTHeaderMeasurement(self.table);
        CGRect narrow = self.table.frame; narrow.size.width = 280; self.table.frame = narrow;
        FBTUIKit26UpdateTableHeaderLayout(self.table);
        NSDictionary *shrunk = FBTHeaderMeasurement(self.table);
        BOOL resized = [wide[@"issues"] count] == 0 && [shrunk[@"issues"] count] == 0 &&
            fabs([wide[@"width"] doubleValue] - 360) <= 1 && fabs([shrunk[@"width"] doubleValue] - 280) <= 1;
        [self record:@"header.resize" pass:resized details:@{@"wide": wide, @"narrow_again": shrunk}];
        [self capture:@"header-resized"];
        [self finish];
    }];
#endif
}
@end

@interface FBTRegressionSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) FBTRegressionRun *run;
@end
@implementation FBTRegressionSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    self.run = [FBTRegressionRun new]; self.run.window = self.window;
    [self.run start];
}
@end

@interface FBTRegressionAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation FBTRegressionAppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Regression" sessionRole:session.role];
    configuration.delegateClass = FBTRegressionSceneDelegate.class;
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(FBTRegressionAppDelegate.class)); }
}
