#import "FBGRMenuTheme.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSInteger const kFBGRTitleLabelTag = 7701;
static NSInteger const kFBGRDetailLabelTag = 7702;

static UIColor *FBGRDynamic(UIColor *light, UIColor *dark) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
            return trait.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        }];
    }
    return dark;
}

UIColor *FBGRBackgroundColor(void) {
    return FBGRDynamic([UIColor colorWithWhite:0.965 alpha:1.0], [UIColor blackColor]);
}
UIColor *FBGRGroupedCellColor(void) {
    return FBGRDynamic([UIColor colorWithWhite:1.0 alpha:1.0], [UIColor colorWithWhite:0.075 alpha:1.0]);
}
UIColor *FBGRTextColor(void) { return UIColor.labelColor ?: UIColor.whiteColor; }
UIColor *FBGRSecondaryTextColor(void) { return UIColor.secondaryLabelColor ?: [UIColor colorWithWhite:0.62 alpha:1.0]; }
UIColor *FBGRSeparatorColor(void) { return UIColor.separatorColor ?: FBGRDynamic([UIColor colorWithWhite:0.78 alpha:1.0], [UIColor colorWithWhite:1.0 alpha:0.10]); }
UIColor *FBGRAccentColor(void) { return UIColor.labelColor ?: UIColor.whiteColor; }

UIFont *FBGRTitleFont(void) { return [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold]; }
UIFont *FBGRDetailFont(void) { return [UIFont systemFontOfSize:8.6 weight:UIFontWeightRegular]; }
UIFont *FBGRRootTitleFont(void) { return [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold]; }
UIFont *FBGRRootDetailFont(void) { return [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular]; }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name ?: @"circle"] ?: [UIImage systemImageNamed:@"circle"];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular scale:UIImageSymbolScaleMedium];
    img = [img imageByApplyingSymbolConfiguration:cfg] ?: img;
    return [img imageWithTintColor:color ?: FBGRSecondaryTextColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIVisualEffect *FBGRCreateRealGlassEffect(void) {
    for (NSString *cn in @[@"UIGlassEffect", @"_UIGlassEffect", @"UILiquidGlassEffect", @"_UILiquidGlassEffect"]) {
        Class cls = NSClassFromString(cn);
        if (!cls) continue;
        SEL effectSel = sel_registerName("effect");
        if ([cls respondsToSelector:effectSel]) {
            id (*msg)(id,SEL) = (id(*)(id,SEL))objc_msgSend;
            id e = msg(cls, effectSel);
            if ([e isKindOfClass:UIVisualEffect.class]) return e;
        }
        id e = [[cls alloc] init];
        if ([e isKindOfClass:UIVisualEffect.class]) return e;
    }
    return nil;
}

UIVisualEffectView *FBGRCreateRealGlassView(void) {
    UIVisualEffect *effect = FBGRCreateRealGlassEffect();
    if (!effect) return nil;
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.userInteractionEnabled = NO;
    v.backgroundColor = UIColor.clearColor;
    return v;
}

void FBGRApplyGlassController(UIViewController *vc) {
    if (!vc) return;
    vc.view.backgroundColor = FBGRBackgroundColor();
    vc.navigationController.view.backgroundColor = FBGRBackgroundColor();
    vc.navigationController.navigationBar.tintColor = FBGRTextColor();
    vc.navigationController.toolbar.tintColor = FBGRTextColor();

    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (!bar) return;
    bar.translucent = YES;
    if (@available(iOS 26.0, *)) {
        // Built with SDK 26: let UIKit own native Liquid Glass chrome.
        return;
    }
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
        [ap configureWithDefaultBackground];
        ap.backgroundColor = FBGRBackgroundColor();
        ap.shadowColor = UIColor.clearColor;
        ap.titleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor(), NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] };
        ap.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor() };
        bar.standardAppearance = ap;
        bar.scrollEdgeAppearance = ap;
        bar.compactAppearance = ap;
    }
}

void FBGRApplyGlassTable(UITableView *tableView) {
    if (!tableView) return;
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    tableView.separatorColor = FBGRSeparatorColor();
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 46.0;
    tableView.contentInset = UIEdgeInsetsMake(12, 0, 24, 0);
    tableView.separatorInset = UIEdgeInsetsMake(0, 54, 0, 0);
    tableView.layoutMargins = UIEdgeInsetsMake(0, 32, 0, 32);
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 18.0;
}

void FBGRApplyGlassCell(UITableViewCell *cell) {
    if (!cell) return;
    cell.backgroundView = nil;
    cell.backgroundColor = FBGRGroupedCellColor();
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = FBGRTextColor();
    cell.detailTextLabel.textColor = FBGRSecondaryTextColor();
    cell.textLabel.font = FBGRRootTitleFont();
    cell.detailTextLabel.font = FBGRRootDetailFont();
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 1;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.preservesSuperviewLayoutMargins = YES;
    cell.layoutMargins = UIEdgeInsetsMake(0, 16, 0, 16);
    cell.separatorInset = UIEdgeInsetsMake(0, 54, 0, 0);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

static UILabel *FBGRLabelInCell(UITableViewCell *cell, NSInteger tag, UIFont *font, UIColor *color) {
    UILabel *label = [cell.contentView viewWithTag:tag];
    if (!label) {
        label = [UILabel new];
        label.tag = tag;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByCharWrapping;
        [cell.contentView addSubview:label];
    }
    label.font = font;
    label.textColor = color;
    return label;
}

static void FBGRRemoveManagedConstraints(UITableViewCell *cell) {
    NSMutableArray<NSLayoutConstraint *> *remove = [NSMutableArray array];
    for (NSLayoutConstraint *c in cell.contentView.constraints) {
        if (c.identifier && [c.identifier hasPrefix:@"FBGRCellText."]) [remove addObject:c];
    }
    if (remove.count) [NSLayoutConstraint deactivateConstraints:remove];
}

void FBGRApplyReadableTextCellWithReservedTrailing(UITableViewCell *cell, NSString *title, NSString *detail, CGFloat reservedTrailing) {
    if (!cell) return;
    FBGRApplyGlassCell(cell);
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;

    UILabel *titleLabel = FBGRLabelInCell(cell, kFBGRTitleLabelTag, FBGRTitleFont(), FBGRTextColor());
    UILabel *detailLabel = FBGRLabelInCell(cell, kFBGRDetailLabelTag, FBGRDetailFont(), FBGRSecondaryTextColor());
    FBGRRemoveManagedConstraints(cell);

    CGFloat trailing = MAX(12.0, reservedTrailing);
    NSArray<NSLayoutConstraint *> *constraints = @[
        [titleLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cell.contentView.trailingAnchor constant:-trailing],
        [titleLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6.0],
        [detailLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:titleLabel.trailingAnchor],
        [detailLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:1.0],
        [detailLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6.0],
    ];
    for (NSLayoutConstraint *c in constraints) c.identifier = @"FBGRCellText.constraint";
    [NSLayoutConstraint activateConstraints:constraints];
    titleLabel.text = title ?: @"";
    detailLabel.text = detail ?: @"";
}

void FBGRApplyReadableTextCell(UITableViewCell *cell, NSString *title, NSString *detail) {
    FBGRApplyReadableTextCellWithReservedTrailing(cell, title, detail, 18.0);
}

void FBGRApplyRootTextCell(UITableViewCell *cell, NSString *title, NSString *detail) {
    if (!cell) return;
    FBGRApplyGlassCell(cell);
    cell.textLabel.text = title ?: @"";
    cell.detailTextLabel.text = detail ?: @"";
    cell.textLabel.font = FBGRRootTitleFont();
    cell.detailTextLabel.font = FBGRRootDetailFont();
    cell.textLabel.textColor = FBGRTextColor();
    cell.detailTextLabel.textColor = FBGRSecondaryTextColor();
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 1;
}

void FBGRApplySearchController(UISearchController *search) {
    if (!search) return;
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.tintColor = FBGRTextColor();
    search.searchBar.placeholder = @"Buscar";
    search.obscuresBackgroundDuringPresentation = NO;
    // Keep this header-safe: no iOS 26-only search bar symbols here.
    // UIKit still renders the search controller natively on-device.
}

void FBGRConfigureCompactSwitch(UISwitch *sw) {
    if (!sw) return;
    sw.transform = CGAffineTransformMakeScale(0.76, 0.76);
    sw.onTintColor = UIColor.systemGrayColor ?: FBGRSecondaryTextColor();
    sw.thumbTintColor = UIColor.whiteColor;
}

void FBGRInstallSwitchInCell(UITableViewCell *cell, UISwitch *sw) {
    if (!cell || !sw) return;
    cell.accessoryView = nil;
    for (UIView *v in cell.contentView.subviews.copy) {
        if ([v isKindOfClass:UISwitch.class]) [v removeFromSuperview];
    }
    NSInteger originalTag = sw.tag;
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:sw];
    [NSLayoutConstraint activateConstraints:@[
        [sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-6.0],
        [sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
    ]];
    sw.tag = originalTag;
}
