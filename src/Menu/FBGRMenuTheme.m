#import "FBGRMenuTheme.h"
#import <objc/message.h>
#import <objc/runtime.h>

static UIColor *FBGRDynamic(UIColor *light, UIColor *dark) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
            return trait.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
        }];
    }
    return dark;
}

UIColor *FBGRBackgroundColor(void) {
    return FBGRDynamic([UIColor colorWithWhite:0.985 alpha:1.0], [UIColor colorWithWhite:0.02 alpha:1.0]);
}
UIColor *FBGRTextColor(void) { return UIColor.labelColor ?: UIColor.whiteColor; }
UIColor *FBGRSecondaryTextColor(void) { return UIColor.secondaryLabelColor ?: [UIColor colorWithWhite:0.68 alpha:1.0]; }
UIColor *FBGRAccentColor(void) { return UIColor.labelColor ?: UIColor.whiteColor; }
UIFont *FBGRTitleFont(void) { return [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold]; }
UIFont *FBGRDetailFont(void) { return [UIFont systemFontOfSize:7.25 weight:UIFontWeightRegular]; }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name ?: @"circle"] ?: [UIImage systemImageNamed:@"circle"];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular scale:UIImageSymbolScaleSmall];
    img = [img imageByApplyingSymbolConfiguration:cfg] ?: img;
    return [img imageWithTintColor:color ?: FBGRAccentColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
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
    v.layer.cornerRadius = 10.0;
    v.layer.masksToBounds = YES;
    v.contentView.backgroundColor = FBGRDynamic([UIColor colorWithWhite:1.0 alpha:0.22], [UIColor colorWithWhite:1.0 alpha:0.055]);
    return v;
}

void FBGRApplyGlassController(UIViewController *vc) {
    vc.view.backgroundColor = FBGRBackgroundColor();
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (bar) {
        bar.tintColor = FBGRTextColor();
        if (@available(iOS 26.0, *)) {
            // Built against SDK 26: leave the native UIKit chrome in charge of Liquid Glass.
        } else {
            UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
            [ap configureWithDefaultBackground];
            ap.backgroundColor = FBGRBackgroundColor();
            ap.titleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor(), NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] };
            ap.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor() };
            bar.standardAppearance = ap;
            bar.scrollEdgeAppearance = ap;
            bar.compactAppearance = ap;
        }
    }
}

void FBGRApplyGlassTable(UITableView *tableView) {
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    tableView.separatorColor = UIColor.separatorColor;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 48.0;
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 8.0;
}

void FBGRApplyGlassCell(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = FBGRTextColor();
    cell.detailTextLabel.textColor = FBGRSecondaryTextColor();
    cell.textLabel.font = FBGRTitleFont();
    cell.detailTextLabel.font = FBGRDetailFont();
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    UIVisualEffectView *glass = FBGRCreateRealGlassView();
    if (glass) {
        UIView *bg = [[UIView alloc] initWithFrame:CGRectZero];
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [bg addSubview:glass];
        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:3],
            [glass.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-3],
            [glass.topAnchor constraintEqualToAnchor:bg.topAnchor constant:2],
            [glass.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor constant:-2],
        ]];
        cell.backgroundView = bg;
    } else {
        cell.backgroundColor = FBGRDynamic([UIColor colorWithWhite:1.0 alpha:0.70], [UIColor colorWithWhite:1.0 alpha:0.045]);
    }
}

void FBGRApplyReadableTextCell(UITableViewCell *cell, NSString *title, NSString *detail) {
    FBGRApplyGlassCell(cell);
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;

    UILabel *titleLabel = [cell.contentView viewWithTag:7701];
    UILabel *detailLabel = [cell.contentView viewWithTag:7702];
    if (!titleLabel) {
        titleLabel = [UILabel new];
        titleLabel.tag = 7701;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.numberOfLines = 0;
        titleLabel.lineBreakMode = NSLineBreakByCharWrapping;
        titleLabel.font = FBGRTitleFont();
        titleLabel.textColor = FBGRTextColor();
        [cell.contentView addSubview:titleLabel];
    }
    if (!detailLabel) {
        detailLabel = [UILabel new];
        detailLabel.tag = 7702;
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        detailLabel.numberOfLines = 0;
        detailLabel.lineBreakMode = NSLineBreakByCharWrapping;
        detailLabel.font = FBGRDetailFont();
        detailLabel.textColor = FBGRSecondaryTextColor();
        [cell.contentView addSubview:detailLabel];
    }
    titleLabel.font = FBGRTitleFont();
    detailLabel.font = FBGRDetailFont();
    titleLabel.textColor = FBGRTextColor();
    detailLabel.textColor = FBGRSecondaryTextColor();
    if (titleLabel.constraints.count == 0 && detailLabel.constraints.count == 0) {
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cell.contentView.trailingAnchor constant:-6],
            [titleLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:7],
            [detailLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [detailLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [detailLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:1],
            [detailLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-7],
        ]];
    }
    titleLabel.text = title ?: @"";
    detailLabel.text = detail ?: @"";
}

void FBGRApplySearchController(UISearchController *search) {
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.tintColor = FBGRTextColor();
    search.searchBar.placeholder = @"Buscar";
    search.obscuresBackgroundDuringPresentation = NO;
}

void FBGRConfigureCompactSwitch(UISwitch *sw) {
    sw.transform = CGAffineTransformMakeScale(0.64, 0.64);
    sw.onTintColor = UIColor.systemGray2Color ?: FBGRSecondaryTextColor();
    sw.thumbTintColor = UIColor.whiteColor;
}
