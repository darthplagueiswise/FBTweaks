#import "FBGRMenuTheme.h"
#import <objc/message.h>

UIColor *FBGRBackgroundColor(void) { return [UIColor blackColor]; }
UIColor *FBGRTextColor(void) { return [UIColor colorWithWhite:0.94 alpha:1.0]; }
UIColor *FBGRSecondaryTextColor(void) { return [UIColor colorWithWhite:0.50 alpha:1.0]; }
UIColor *FBGRAccentColor(void) { return UIColor.systemBlueColor; }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name ?: @""];
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
    v.layer.cornerRadius = 18.0;
    v.layer.masksToBounds = YES;
    v.alpha = 0.72;
    return v;
}

void FBGRApplyGlassController(UIViewController *vc) {
    vc.view.backgroundColor = UIColor.blackColor;
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (bar) {
        UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
        [ap configureWithTransparentBackground];
        ap.backgroundColor = UIColor.clearColor;
        ap.shadowColor = UIColor.clearColor;
        ap.titleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor(), NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightRegular] };
        ap.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor(), NSFontAttributeName: [UIFont systemFontOfSize:22 weight:UIFontWeightRegular] };
        bar.standardAppearance = ap;
        bar.scrollEdgeAppearance = ap;
        bar.compactAppearance = ap;
        bar.tintColor = FBGRTextColor();
        bar.translucent = YES;
    }
}

void FBGRApplyGlassTable(UITableView *tableView) {
    tableView.backgroundColor = UIColor.blackColor;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 58.0;
    tableView.sectionHeaderTopPadding = 10.0;
}

static UIView *FBGRCellBackground(BOOL selected) {
    UIView *bg = [UIView new];
    bg.backgroundColor = selected ? [UIColor colorWithWhite:0.16 alpha:1.0] : [UIColor colorWithWhite:0.075 alpha:1.0];
    bg.layer.cornerRadius = 18.0;
    bg.layer.masksToBounds = YES;
    bg.layer.borderWidth = 0.6;
    bg.layer.borderColor = [UIColor colorWithWhite:0.22 alpha:1.0].CGColor;
    return bg;
}

void FBGRApplyGlassCell(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.tintColor = FBGRAccentColor();
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.backgroundView = FBGRCellBackground(NO);
    cell.selectedBackgroundView = FBGRCellBackground(YES);
}

void FBGRApplySearchController(UISearchController *search) {
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.tintColor = FBGRTextColor();
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.backgroundColor = UIColor.clearColor;
    UITextField *tf = search.searchBar.searchTextField;
    tf.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    tf.textColor = FBGRTextColor();
    tf.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
}

static UIListContentConfiguration *FBGRBaseConfig(NSString *title) {
    UIListContentConfiguration *cfg = [UIListContentConfiguration cellConfiguration];
    cfg.text = title ?: @"";
    cfg.textProperties.color = FBGRTextColor();
    cfg.textProperties.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    cfg.textProperties.numberOfLines = 0;
    cfg.textProperties.lineBreakMode = NSLineBreakByCharWrapping;
    cfg.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, 20, 10, 14);
    return cfg;
}

void FBGRConfigureCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIImage *image) {
    FBGRApplyGlassCell(cell);
    cell.contentConfiguration = FBGRBaseConfig(title);
    cell.accessoryView = nil;
    cell.imageView.image = nil;
    cell.detailTextLabel.text = nil;
}

void FBGRConfigureSwitchCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UISwitch *sw, UIImage *image) {
    FBGRApplyGlassCell(cell);
    cell.contentConfiguration = FBGRBaseConfig(title);
    cell.accessoryView = sw;
    cell.imageView.image = nil;
    cell.detailTextLabel.text = nil;
}
