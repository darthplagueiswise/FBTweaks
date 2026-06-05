#import "FBGRMenuTheme.h"
#import <objc/message.h>

static UIColor *FBGRDynamic(UIColor *light, UIColor *dark) {
    if (@available(iOS 13.0, *)) return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) { return trait.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light; }];
    return light;
}

UIColor *FBGRBackgroundColor(void) { return FBGRDynamic(UIColor.whiteColor, UIColor.blackColor); }
UIColor *FBGRTextColor(void) { return UIColor.labelColor ?: FBGRDynamic(UIColor.blackColor, UIColor.whiteColor); }
UIColor *FBGRSecondaryTextColor(void) { return UIColor.secondaryLabelColor ?: FBGRDynamic([UIColor colorWithWhite:0.35 alpha:1.0], [UIColor colorWithWhite:0.72 alpha:1.0]); }
UIColor *FBGRAccentColor(void) { return UIColor.labelColor ?: FBGRTextColor(); }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name ?: @"circle"];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightRegular scale:UIImageSymbolScaleMedium];
        img = [img imageByApplyingSymbolConfiguration:cfg] ?: img;
    }
    return [[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageWithTintColor:color ?: FBGRSecondaryTextColor() renderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIVisualEffect *FBGRCreateEffectByName(NSString *cn) {
    Class cls = NSClassFromString(cn);
    if (!cls) return nil;
    id effect = nil;
    @try { effect = [[cls alloc] init]; } @catch (__unused NSException *e) { effect = nil; }
    return [effect isKindOfClass:UIVisualEffect.class] ? effect : nil;
}

static UIVisualEffect *FBGRCreateRealGlassEffect(void) { return FBGRCreateEffectByName(@"UIGlassEffect"); }
static UIVisualEffect *FBGRCreateRealGlassContainerEffect(CGFloat spacing) {
    UIVisualEffect *effect = FBGRCreateEffectByName(@"UIGlassContainerEffect");
    if (!effect) return nil;
    @try { [effect setValue:@(spacing) forKey:@"spacing"]; } @catch (__unused NSException *e) {}
    return effect;
}

UIVisualEffectView *FBGRCreateRealGlassView(void) {
    UIVisualEffect *effect = FBGRCreateRealGlassEffect();
    if (!effect) return nil;
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.userInteractionEnabled = NO;
    v.backgroundColor = UIColor.clearColor;
    v.layer.cornerRadius = 18.0;
    if (@available(iOS 13.0, *)) v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.masksToBounds = YES;
    return v;
}

void FBGRApplyGlassController(UIViewController *vc) {
    vc.view.backgroundColor = FBGRBackgroundColor();
    if (@available(iOS 26.0, *)) {
        UIVisualEffect *container = FBGRCreateRealGlassContainerEffect(18.0);
        if (container && ![vc.view viewWithTag:8801]) {
            UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:container];
            bg.tag = 8801;
            bg.frame = vc.view.bounds;
            bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            bg.userInteractionEnabled = NO;
            [vc.view insertSubview:bg atIndex:0];
        }
    }
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (bar) {
        bar.tintColor = FBGRTextColor();
        if (@available(iOS 26.0, *)) return; // UIKit owns native Liquid Glass chrome.
        if (@available(iOS 13.0, *)) {
            UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
            [ap configureWithDefaultBackground];
            ap.titleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor() };
            ap.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor() };
            bar.standardAppearance = ap; bar.scrollEdgeAppearance = ap; bar.compactAppearance = ap;
        }
    }
}

void FBGRApplyGlassTable(UITableView *tableView) {
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    tableView.separatorColor = UIColor.separatorColor;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 88.0;
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 12.0;
}

void FBGRApplyGlassCell(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = FBGRTextColor();
    cell.detailTextLabel.textColor = FBGRSecondaryTextColor();
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    UIVisualEffectView *glass = FBGRCreateRealGlassView();
    if (glass) {
        UIView *bg = [[UIView alloc] initWithFrame:CGRectZero];
        bg.backgroundColor = UIColor.clearColor;
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [bg addSubview:glass];
        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:8],
            [glass.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-8],
            [glass.topAnchor constraintEqualToAnchor:bg.topAnchor constant:4],
            [glass.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor constant:-4],
        ]];
        cell.backgroundView = bg;
    } else {
        cell.backgroundColor = FBGRDynamic([UIColor colorWithWhite:0.96 alpha:1.0], [UIColor colorWithWhite:0.08 alpha:1.0]);
    }
}

void FBGRApplyReadableTextCell(UITableViewCell *cell, NSString *title, NSString *detail) {
    FBGRApplyGlassCell(cell);
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    UILabel *titleLabel = [cell.contentView viewWithTag:7701];
    UILabel *detailLabel = [cell.contentView viewWithTag:7702];
    if (!titleLabel) {
        titleLabel = [UILabel new]; titleLabel.tag = 7701; titleLabel.translatesAutoresizingMaskIntoConstraints = NO; titleLabel.numberOfLines = 0; titleLabel.lineBreakMode = NSLineBreakByCharWrapping; titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; titleLabel.textColor = FBGRTextColor(); [cell.contentView addSubview:titleLabel];
    }
    if (!detailLabel) {
        detailLabel = [UILabel new]; detailLabel.tag = 7702; detailLabel.translatesAutoresizingMaskIntoConstraints = NO; detailLabel.numberOfLines = 0; detailLabel.lineBreakMode = NSLineBreakByCharWrapping; detailLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular]; detailLabel.textColor = FBGRSecondaryTextColor(); [cell.contentView addSubview:detailLabel];
    }
    if (titleLabel.constraints.count == 0 && detailLabel.constraints.count == 0) {
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
            [titleLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [detailLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [detailLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [detailLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],
            [detailLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        ]];
    }
    titleLabel.text = title ?: @"";
    detailLabel.text = detail ?: @"";
}

void FBGRApplySearchController(UISearchController *search) {
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.tintColor = FBGRTextColor();
    search.obscuresBackgroundDuringPresentation = NO;
}
