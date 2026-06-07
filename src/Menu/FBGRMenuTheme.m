#import "FBGRMenuTheme.h"
#import <objc/message.h>

UIColor *FBGRBackgroundColor(void) { return [UIColor colorWithWhite:0.02 alpha:1.0]; }
UIColor *FBGRTextColor(void) { return UIColor.labelColor; }
UIColor *FBGRSecondaryTextColor(void) { return UIColor.secondaryLabelColor; }
UIColor *FBGRAccentColor(void) { return UIColor.systemCyanColor; }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name ?: @"circle"];
    return color ? [img imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : img;
}

static UIVisualEffect *FBGRCreateRealGlassEffect(void) {
    for (NSString *cn in @[@"UIGlassEffect", @"_UIGlassEffect", @"UILiquidGlassEffect", @"_UILiquidGlassEffect"]) {
        Class cls = NSClassFromString(cn);
        if (!cls) continue;
        SEL effectSel = sel_registerName("effect");
        if ([cls respondsToSelector:effectSel]) {
            id (*msg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            id e = msg(cls, effectSel);
            if ([e isKindOfClass:UIVisualEffect.class]) return e;
        }
        @try {
            id e = [[cls alloc] init];
            if ([e isKindOfClass:UIVisualEffect.class]) return e;
        } @catch (__unused NSException *ex) {}
    }
    return nil;
}

UIVisualEffectView *FBGRCreateRealGlassView(void) {
    UIVisualEffect *effect = FBGRCreateRealGlassEffect();
    if (!effect) return nil;
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.userInteractionEnabled = NO;
    v.layer.cornerRadius = 20.0;
    v.layer.masksToBounds = YES;
    v.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    v.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.18].CGColor;
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
    tableView.estimatedRowHeight = 82.0;
}

void FBGRApplyGlassCell(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.tintColor = FBGRAccentColor();
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    UIVisualEffectView *glass = FBGRCreateRealGlassView();
    if (glass) {
        UIView *bg = [[UIView alloc] initWithFrame:CGRectZero];
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [bg addSubview:glass];
        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:6],
            [glass.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-6],
            [glass.topAnchor constraintEqualToAnchor:bg.topAnchor constant:4],
            [glass.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor constant:-4],
        ]];
        cell.backgroundView = bg;
    } else {
        UIView *bg = [UIView new];
        bg.backgroundColor = [UIColor.secondarySystemGroupedBackgroundColor colorWithAlphaComponent:0.72];
        bg.layer.cornerRadius = 20;
        bg.layer.masksToBounds = YES;
        cell.backgroundView = bg;
    }
}

void FBGRApplySearchController(UISearchController *search) {
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.tintColor = FBGRAccentColor();
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.backgroundColor = UIColor.clearColor;
}

static UIListContentConfiguration *FBGRBaseConfig(NSString *title, NSString *subtitle) {
    UIListContentConfiguration *cfg = [UIListContentConfiguration subtitleCellConfiguration];
    cfg.text = title ?: @"";
    cfg.secondaryText = subtitle ?: @"";
    cfg.textProperties.color = FBGRTextColor();
    cfg.textProperties.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    cfg.textProperties.numberOfLines = 0;
    cfg.secondaryTextProperties.color = FBGRSecondaryTextColor();
    cfg.secondaryTextProperties.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cfg.secondaryTextProperties.numberOfLines = 0;
    cfg.imageProperties.maximumSize = CGSizeMake(26, 26);
    cfg.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(12, 14, 12, 14);
    return cfg;
}

void FBGRConfigureCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIImage *image) {
    FBGRApplyGlassCell(cell);
    UIListContentConfiguration *cfg = FBGRBaseConfig(title, subtitle);
    cfg.image = image;
    cell.contentConfiguration = cfg;
    cell.accessoryView = nil;
}

void FBGRConfigureSwitchCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UISwitch *sw, UIImage *image) {
    FBGRApplyGlassCell(cell);
    UIListContentConfiguration *cfg = FBGRBaseConfig(title, subtitle);
    cfg.image = image;
    cell.contentConfiguration = cfg;
    cell.accessoryView = sw;
}
