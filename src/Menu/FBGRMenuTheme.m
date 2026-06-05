#import "FBGRMenuTheme.h"
#import <objc/message.h>

UIColor *FBGRBackgroundColor(void) { return [UIColor colorWithWhite:0.02 alpha:1.0]; }
UIColor *FBGRTextColor(void) { return UIColor.labelColor; }
UIColor *FBGRSecondaryTextColor(void) { return UIColor.secondaryLabelColor; }
UIColor *FBGRAccentColor(void) { return UIColor.systemCyanColor; }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name];
    return [img imageWithTintColor:color ?: FBGRAccentColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIVisualEffect *FBGRCreateRealGlassEffect(void) {
    NSArray<NSString *> *classes = @[@"UIGlassEffect", @"_UIGlassEffect", @"UILiquidGlassEffect", @"_UILiquidGlassEffect"];
    for (NSString *cn in classes) {
        Class cls = NSClassFromString(cn);
        if (!cls) continue;
        SEL effectSel = sel_registerName("effect");
        if ([cls respondsToSelector:effectSel]) {
            id (*msg)(id,SEL) = (id(*)(id,SEL))objc_msgSend;
            id e = msg(cls, effectSel);
            if ([e isKindOfClass:UIVisualEffect.class]) return e;
        }
        SEL initSel = sel_registerName("init");
        if ([cls instancesRespondToSelector:initSel]) {
            id e = [[cls alloc] init];
            if ([e isKindOfClass:UIVisualEffect.class]) return e;
        }
    }
    return nil;
}

UIVisualEffectView *FBGRCreateRealGlassView(void) {
    UIVisualEffect *effect = FBGRCreateRealGlassEffect();
    if (!effect) return nil;
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.userInteractionEnabled = NO;
    v.layer.cornerRadius = 24.0;
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
}

void FBGRApplyGlassCell(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = FBGRTextColor();
    cell.detailTextLabel.textColor = FBGRSecondaryTextColor();
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

void FBGRApplySearchController(UISearchController *search) {
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.tintColor = FBGRAccentColor();
    search.obscuresBackgroundDuringPresentation = NO;
}
