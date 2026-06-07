#import "FBGRMenuTheme.h"
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

static NSInteger const kFBGRCellContentTag = 0xF81711;
static NSInteger const kFBGRCellGlassTag = 0xF81712;

static BOOL FBGRDarkMode(void) {
    return UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

UIColor *FBGRBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) return [UIColor colorWithRed:0.070 green:0.074 blue:0.090 alpha:1.0];
        return [UIColor colorWithRed:0.948 green:0.956 blue:0.972 alpha:1.0];
    }];
}

UIColor *FBGRGroupedCellColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) return [UIColor colorWithRed:0.145 green:0.150 blue:0.172 alpha:0.78];
        return [UIColor colorWithWhite:1.0 alpha:0.72];
    }];
}

UIColor *FBGRTextColor(void) { return UIColor.labelColor; }
UIColor *FBGRSecondaryTextColor(void) { return UIColor.secondaryLabelColor; }
UIColor *FBGRAccentColor(void) { return UIColor.systemCyanColor; }

UIImage *FBGRSymbol(NSString *name, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name ?: @""];
    return [img imageWithTintColor:color ?: FBGRAccentColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static BOOL FBGRIsIOS26OrNewer(void) { if (@available(iOS 26.0, *)) return YES; return NO; }

static UIVisualEffect *FBGRCreateGlassEffect(void) {
    if (!FBGRIsIOS26OrNewer()) return nil;
    for (NSString *className in @[@"UIGlassEffect", @"UILiquidGlassEffect", @"_UIGlassEffect", @"_UILiquidGlassEffect"]) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        SEL effectSel = NSSelectorFromString(@"effect");
        if ([cls respondsToSelector:effectSel]) {
            id e = ((id (*)(id, SEL))objc_msgSend)(cls, effectSel);
            if ([e isKindOfClass:UIVisualEffect.class]) return e;
        }
        SEL styleSel = NSSelectorFromString(@"effectWithStyle:");
        if ([cls respondsToSelector:styleSel]) {
            id e = ((id (*)(id, SEL, NSInteger))objc_msgSend)(cls, styleSel, 1);
            if ([e isKindOfClass:UIVisualEffect.class]) return e;
        }
    }
    return nil;
}

static void FBGRRound(UIView *v, CGFloat radius) {
    if (!v) return;
    v.layer.cornerRadius = radius;
    if ([v.layer respondsToSelector:@selector(setCornerCurve:)]) v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.masksToBounds = YES;
}

static UIView *FBGRCardView(void) {
    UIView *card = [UIView new];
    card.tag = kFBGRCellGlassTag;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = FBGRGroupedCellColor();
    card.layer.borderWidth = 0.55;
    card.layer.borderColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        return trait.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.11] : [UIColor colorWithWhite:0.0 alpha:0.08];
    }].CGColor;
    card.layer.shadowColor = [UIColor colorWithWhite:0.0 alpha:1.0].CGColor;
    card.layer.shadowOpacity = FBGRDarkMode() ? 0.18 : 0.08;
    card.layer.shadowRadius = 12.0;
    card.layer.shadowOffset = CGSizeMake(0, 5);
    FBGRRound(card, 20.0);

    UIVisualEffect *effect = FBGRCreateGlassEffect();
    if (effect) {
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        glass.userInteractionEnabled = NO;
        [card insertSubview:glass atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [glass.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [glass.topAnchor constraintEqualToAnchor:card.topAnchor],
            [glass.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        ]];
        card.backgroundColor = UIColor.clearColor;
    }
    return card;
}

void FBGRApplyGlassController(UIViewController *vc) {
    if (!vc) return;
    vc.view.backgroundColor = FBGRBackgroundColor();
    if (FBGRIsIOS26OrNewer()) {
        SEL preferred = NSSelectorFromString(@"setPreferredContainerBackgroundStyle:");
        if ([vc respondsToSelector:preferred]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(vc, preferred, 1);
    }
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (!bar) return;
    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithTransparentBackground];
    ap.backgroundColor = UIColor.clearColor;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{NSForegroundColorAttributeName: FBGRTextColor(), NSFontAttributeName: [UIFont systemFontOfSize:16.5 weight:UIFontWeightMedium]};
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
    tableView.estimatedRowHeight = 58.0;
    tableView.contentInset = UIEdgeInsetsMake(8.0, 0.0, 18.0, 0.0);
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 4.0;
}

void FBGRApplyGlassCell(UITableViewCell *cell) {
    if (!cell) return;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.tintColor = FBGRAccentColor();
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.backgroundView = nil;
    UIView *sel = [UIView new];
    sel.backgroundColor = UIColor.tertiarySystemFillColor;
    FBGRRound(sel, 20.0);
    cell.selectedBackgroundView = sel;
}

void FBGRApplySearchController(UISearchController *search) {
    if (!search) return;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.backgroundImage = UIImage.new;
    search.searchBar.tintColor = FBGRAccentColor();
    UITextField *tf = search.searchBar.searchTextField;
    tf.textColor = FBGRTextColor();
    tf.tintColor = FBGRAccentColor();
    tf.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    tf.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *trait) {
        if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) return [UIColor colorWithWhite:1.0 alpha:0.105];
        return [UIColor colorWithWhite:1.0 alpha:0.70];
    }];
    FBGRRound(tf, 16.0);
}

static NSString *FBGRReadableTitle(NSString *title) {
    if (!title.length) return @"";
    NSString *s = [title stringByReplacingOccurrencesOfString:@":" withString:@":\n"];
    return s;
}

static void FBGRClearCustomContent(UITableViewCell *cell) {
    cell.contentConfiguration = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    for (UIView *v in cell.contentView.subviews.copy) {
        if (v.tag == kFBGRCellContentTag || v.tag == kFBGRCellGlassTag) [v removeFromSuperview];
    }
}

static UIView *FBGRIconPill(UIImage *image) {
    if (!image) return nil;
    UIView *pill = [UIView new];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [FBGRAccentColor() colorWithAlphaComponent:0.16];
    FBGRRound(pill, 10.0);
    UIImageView *iv = [[UIImageView alloc] initWithImage:image];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [pill addSubview:iv];
    [NSLayoutConstraint activateConstraints:@[
        [pill.widthAnchor constraintEqualToConstant:30.0],
        [pill.heightAnchor constraintEqualToConstant:30.0],
        [iv.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:17.0],
        [iv.heightAnchor constraintEqualToConstant:17.0],
    ]];
    return pill;
}

static UIView *FBGRInstallContent(UITableViewCell *cell, NSString *title, NSString *subtitle, UIImage *image, UIView *rightView, BOOL disclosure) {
    FBGRClearCustomContent(cell);
    FBGRApplyGlassCell(cell);

    UIView *card = FBGRCardView();
    [cell.contentView addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14.0],
        [card.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14.0],
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:5.0],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-5.0],
    ]];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = FBGRReadableTitle(title);
    titleLabel.textColor = FBGRTextColor();
    titleLabel.font = [UIFont monospacedSystemFontOfSize:12.8 weight:UIFontWeightRegular];
    titleLabel.numberOfLines = 0;
    titleLabel.lineBreakMode = NSLineBreakByCharWrapping;
    titleLabel.adjustsFontForContentSizeCategory = YES;

    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2.0;
    texts.alignment = UIStackViewAlignmentFill;

    if (subtitle.length) {
        UILabel *sub = [UILabel new];
        sub.text = subtitle;
        sub.textColor = FBGRSecondaryTextColor();
        sub.font = [UIFont monospacedSystemFontOfSize:10.7 weight:UIFontWeightRegular];
        sub.numberOfLines = 1;
        sub.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [texts addArrangedSubview:sub];
    }

    NSMutableArray *parts = [NSMutableArray array];
    UIView *pill = FBGRIconPill(image);
    if (pill) [parts addObject:pill];
    [parts addObject:texts];

    if (rightView) {
        if ([rightView isKindOfClass:UISwitch.class]) rightView.transform = CGAffineTransformMakeScale(0.84, 0.84);
        [parts addObject:rightView];
    }

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:parts];
    row.tag = kFBGRCellContentTag;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = pill ? 10.0 : 0.0;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:10.0],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10.0],
    ]];

    [texts setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [texts setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    if (rightView) {
        [rightView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [rightView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    cell.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return card;
}

void FBGRConfigureCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIImage *image) {
    FBGRInstallContent(cell, title, subtitle, image, nil, YES);
}

void FBGRConfigureSwitchCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UISwitch *sw, UIImage *image) {
    FBGRInstallContent(cell, title, subtitle, sw, nil, NO);
}
