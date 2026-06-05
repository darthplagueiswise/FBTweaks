#import "FBGRMenuTheme.h"
#import <objc/message.h>

UIColor *FBGRBackgroundColor(void) { return [UIColor colorWithWhite:0.02 alpha:1.0]; }
UIColor *FBGRTextColor(void) { return UIColor.labelColor; }
UIColor *FBGRSecondaryTextColor(void) { return UIColor.secondaryLabelColor; }
UIColor *FBGRAccentColor(void) { return UIColor.systemCyanColor; }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name ?: @"circle"];
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
    v.layer.cornerRadius = 22.0;
    v.layer.masksToBounds = YES;
    return v;
}

void FBGRApplyGlassController(UIViewController *vc) {
    vc.view.backgroundColor = FBGRBackgroundColor();
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (bar) {
        UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
        [ap configureWithTransparentBackground];
        ap.titleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor() };
        ap.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor() };
        bar.standardAppearance = ap;
        bar.scrollEdgeAppearance = ap;
        bar.compactAppearance = ap;
        bar.tintColor = FBGRAccentColor();
    }
}

void FBGRApplyGlassTable(UITableView *tableView) {
    tableView.backgroundColor = UIColor.clearColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 88.0;
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
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [bg addSubview:glass];
        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:8],
            [glass.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-8],
            [glass.topAnchor constraintEqualToAnchor:bg.topAnchor constant:4],
            [glass.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor constant:-4],
        ]];
        cell.backgroundView = bg;
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
        titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        titleLabel.textColor = FBGRTextColor();
        [cell.contentView addSubview:titleLabel];
    }
    if (!detailLabel) {
        detailLabel = [UILabel new];
        detailLabel.tag = 7702;
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        detailLabel.numberOfLines = 0;
        detailLabel.lineBreakMode = NSLineBreakByCharWrapping;
        detailLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        detailLabel.textColor = FBGRSecondaryTextColor();
        [cell.contentView addSubview:detailLabel];
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
    search.searchBar.tintColor = FBGRAccentColor();
    search.obscuresBackgroundDuringPresentation = NO;
}
