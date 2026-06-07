#import "FBGRMenuTheme.h"
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

static NSInteger const kFBGRCellStackTag = 0xF81701;
static NSInteger const kFBGRGlassBackgroundTag = 0xF81702;

UIColor *FBGRBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.045 alpha:1.0]
            : [UIColor colorWithWhite:0.965 alpha:1.0];
    }];
}

UIColor *FBGRGroupedCellColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.13 alpha:0.72]
            : [UIColor colorWithWhite:1.0 alpha:0.62];
    }];
}

UIColor *FBGRTextColor(void) { return UIColor.labelColor; }
UIColor *FBGRSecondaryTextColor(void) { return UIColor.secondaryLabelColor; }
UIColor *FBGRAccentColor(void) { return UIColor.systemBlueColor; }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name ?: @""];
    return [img imageWithTintColor:color ?: FBGRAccentColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static BOOL FBGRIsIOS26OrNewer(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

static UIVisualEffect *FBGRCreateGlassEffect(BOOL clearStyle, BOOL interactive, UIColor *tintColor) {
    if (!FBGRIsIOS26OrNewer()) return nil;
    Class cls = NSClassFromString(@"UIGlassEffect") ?: NSClassFromString(@"_UIGlassEffect") ?: NSClassFromString(@"UILiquidGlassEffect") ?: NSClassFromString(@"_UILiquidGlassEffect");
    if (!cls) return nil;

    id effect = nil;
    SEL styled = NSSelectorFromString(@"effectWithStyle:");
    if ([cls respondsToSelector:styled]) {
        NSInteger style = clearStyle ? 0 : 1;
        effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(cls, styled, style);
    }
    if (!effect) {
        SEL plain = NSSelectorFromString(@"effect");
        if ([cls respondsToSelector:plain]) effect = ((id (*)(id, SEL))objc_msgSend)(cls, plain);
    }
    if (![effect isKindOfClass:UIVisualEffect.class]) return nil;

    SEL setInteractive = NSSelectorFromString(@"setInteractive:");
    if ([effect respondsToSelector:setInteractive]) ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, setInteractive, interactive);
    SEL setTint = NSSelectorFromString(@"setTintColor:");
    if (tintColor && [effect respondsToSelector:setTint]) ((void (*)(id, SEL, id))objc_msgSend)(effect, setTint, tintColor);
    return effect;
}

static void FBGRApplyContinuousCorner(UIView *v, CGFloat radius) {
    v.layer.cornerRadius = radius;
    if ([v.layer respondsToSelector:@selector(setCornerCurve:)]) v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.masksToBounds = YES;
}

static UIVisualEffectView *FBGREnsureGlassBackground(UIView *view, CGFloat radius, BOOL interactive) {
    if (!view) return nil;
    UIVisualEffect *effect = FBGRCreateGlassEffect(NO, interactive, nil);
    UIVisualEffectView *glass = (UIVisualEffectView *)[view viewWithTag:kFBGRGlassBackgroundTag];
    if (![glass isKindOfClass:UIVisualEffectView.class]) {
        glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.tag = kFBGRGlassBackgroundTag;
        glass.userInteractionEnabled = NO;
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [view insertSubview:glass atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
            [glass.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
            [glass.topAnchor constraintEqualToAnchor:view.topAnchor],
            [glass.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        ]];
    } else {
        glass.effect = effect;
    }
    if (effect) {
        view.backgroundColor = UIColor.clearColor;
        glass.backgroundColor = UIColor.clearColor;
        glass.contentView.backgroundColor = UIColor.clearColor;
    } else {
        view.backgroundColor = FBGRGroupedCellColor();
    }
    FBGRApplyContinuousCorner(view, radius);
    FBGRApplyContinuousCorner(glass, radius);
    view.layer.borderWidth = 0.5;
    view.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.075]
            : [UIColor colorWithWhite:0.0 alpha:0.075];
    }].CGColor;
    return glass;
}

void FBGRApplyGlassController(UIViewController *vc) {
    if (!vc) return;
    vc.view.backgroundColor = FBGRBackgroundColor();
    SEL preferred = NSSelectorFromString(@"setPreferredContainerBackgroundStyle:");
    SEL direct = NSSelectorFromString(@"setContainerBackgroundStyle:");
    if (FBGRIsIOS26OrNewer() && [vc respondsToSelector:preferred]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(vc, preferred, 1);
    } else if (FBGRIsIOS26OrNewer() && [vc respondsToSelector:direct]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(vc, direct, 1);
    }

    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (!bar) return;
    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithTransparentBackground];
    ap.backgroundColor = UIColor.clearColor;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor(), NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] };
    ap.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: FBGRTextColor(), NSFontAttributeName: [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold] };
    bar.standardAppearance = ap;
    bar.scrollEdgeAppearance = ap;
    bar.compactAppearance = ap;
    bar.tintColor = FBGRAccentColor();
    bar.translucent = YES;
}

void FBGRApplyGlassTable(UITableView *tableView) {
    if (!tableView) return;
    tableView.backgroundColor = UIColor.clearColor;
    tableView.backgroundView = nil;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 56.0;
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 0.0;
    if (FBGRIsIOS26OrNewer()) {
        UIVisualEffect *effect = FBGRCreateGlassEffect(YES, NO, nil);
        SEL setBackgroundEffect = NSSelectorFromString(@"setBackgroundEffect:");
        if (effect && [tableView respondsToSelector:setBackgroundEffect]) ((void (*)(id, SEL, id))objc_msgSend)(tableView, setBackgroundEffect, effect);
    }
}

void FBGRApplyGlassCell(UITableViewCell *cell) {
    if (!cell) return;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.tintColor = FBGRAccentColor();
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    UIView *bg = [UIView new];
    bg.backgroundColor = FBGRGroupedCellColor();
    FBGREnsureGlassBackground(bg, 18.0, NO);
    cell.backgroundView = bg;

    UIView *sel = [UIView new];
    sel.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.10]
            : [UIColor colorWithWhite:0.0 alpha:0.07];
    }];
    FBGRApplyContinuousCorner(sel, 18.0);
    cell.selectedBackgroundView = sel;
}

void FBGRApplySearchController(UISearchController *search) {
    if (!search) return;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.backgroundImage = UIImage.new;
    search.searchBar.backgroundColor = UIColor.clearColor;
    search.searchBar.barTintColor = UIColor.clearColor;
    search.searchBar.tintColor = FBGRAccentColor();

    UITextField *tf = search.searchBar.searchTextField;
    tf.textColor = FBGRTextColor();
    tf.tintColor = FBGRAccentColor();
    tf.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    tf.background = nil;
    tf.disabledBackground = nil;
    tf.backgroundColor = UIColor.clearColor;
    tf.layer.backgroundColor = UIColor.clearColor.CGColor;
    tf.borderStyle = UITextBorderStyleNone;
    tf.leftView.tintColor = FBGRSecondaryTextColor();
    tf.rightView.tintColor = FBGRSecondaryTextColor();
    FBGREnsureGlassBackground(tf, 16.0, YES);
}

static void FBGRClearCustomContent(UITableViewCell *cell) {
    cell.contentConfiguration = nil;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    for (UIView *v in cell.contentView.subviews.copy) {
        if (v.tag == kFBGRCellStackTag) [v removeFromSuperview];
    }
}

static UIStackView *FBGRInstallTextStack(UITableViewCell *cell, NSString *title, NSString *subtitle) {
    FBGRClearCustomContent(cell);
    UILabel *titleLabel = [UILabel new];
    titleLabel.text = title ?: @"";
    titleLabel.textColor = FBGRTextColor();
    titleLabel.font = [UIFont systemFontOfSize:13.2 weight:UIFontWeightRegular];
    titleLabel.numberOfLines = 0;
    titleLabel.lineBreakMode = NSLineBreakByCharWrapping;
    titleLabel.adjustsFontForContentSizeCategory = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel]];
    stack.tag = kFBGRCellStackTag;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 2.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    if (subtitle.length) {
        UILabel *sub = [UILabel new];
        sub.text = subtitle;
        sub.textColor = FBGRSecondaryTextColor();
        sub.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
        sub.numberOfLines = 1;
        sub.lineBreakMode = NSLineBreakByTruncatingTail;
        [stack addArrangedSubview:sub];
    }

    [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-10.0],
        [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
    ]];
    return stack;
}

void FBGRConfigureCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIImage *image) {
    FBGRApplyGlassCell(cell);
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    FBGRInstallTextStack(cell, title, subtitle);
}

void FBGRConfigureSwitchCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UISwitch *sw, UIImage *image) {
    FBGRApplyGlassCell(cell);
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = sw;
    if (sw) {
        sw.onTintColor = FBGRAccentColor();
    }
    FBGRInstallTextStack(cell, title, subtitle);
}
