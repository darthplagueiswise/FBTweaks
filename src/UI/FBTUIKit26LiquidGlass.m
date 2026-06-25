#import "FBTUIKit26LiquidGlass.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

static UIColor *FBTUIKit26TintColor(void) { return [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0]; }

static NSInteger const kFBTUIKit26GlassBackgroundTag = 0x51C126;

static UIColor *FBTUIKit26BorderColor(void);
static UIVisualEffectView *FBTUIKit26EnsureGlassBackground(UIView *view, CGFloat radius, BOOL interactive, BOOL clearStyle, UIColor *tintColor);

static NSInteger const kFBTUIKit26TitleBubbleTag = 0x51C260;

@interface FBTUIKit26TitleBubbleView : UIVisualEffectView
@property (nonatomic, strong) UILabel *label;
- (void)configureWithTitle:(NSString *)title;
@end

@implementation FBTUIKit26TitleBubbleView

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithEffect:FBTUIKit26GlassEffect(NO, YES, nil)];
    if (self) {
        self.tag = kFBTUIKit26TitleBubbleTag;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = FBTUIKit26PanelFillColor();
        self.layer.cornerRadius = 20.0;
        if ([self.layer respondsToSelector:@selector(setCornerCurve:)]) self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _label = [UILabel new];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.textColor = UIColor.labelColor;
        _label.adjustsFontForContentSizeCategory = YES;
        _label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:20.0 weight:UIFontWeightBold]];
        _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _label.numberOfLines = 1;
        [self.contentView addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.5],
            [_label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
            [_label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],
            [_label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.5],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:39.0],
        ]];
        [self configureWithTitle:title];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    NSString *title = self.label.text ?: @"";
    CGSize textSize = [title sizeWithAttributes:@{ NSFontAttributeName: self.label.font ?: [UIFont boldSystemFontOfSize:20.0] }];
    CGFloat maxWidth = MIN(UIScreen.mainScreen.bounds.size.width - 150.0, 300.0);
    CGFloat width = MIN(MAX(78.0, ceil(textSize.width) + 38.0), MAX(120.0, maxWidth));
    return CGSizeMake(width, 40.0);
}

- (CGSize)sizeThatFits:(CGSize)size { return self.intrinsicContentSize; }

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.effect = FBTUIKit26GlassEffect(NO, YES, nil);
    self.contentView.backgroundColor = FBTUIKit26PanelFillColor();
}

- (void)configureWithTitle:(NSString *)title {
    self.label.text = title ?: @"";
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

@end

BOOL FBTUIKit26IsAvailable(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

UIVisualEffect *FBTUIKit26GlassEffect(BOOL clearStyle, BOOL interactive, UIColor *tintColor) {
    if (@available(iOS 26.0, *)) {
        Class glassClass = NSClassFromString(@"UIGlassEffect");
        SEL factory = NSSelectorFromString(@"effectWithStyle:");
        if (glassClass && [glassClass respondsToSelector:factory]) {
            id effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass, factory, clearStyle ? 1 : 0);
            SEL setInteractive = NSSelectorFromString(@"setInteractive:");
            if (effect && [effect respondsToSelector:setInteractive]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, setInteractive, interactive);
            }
            SEL setTintColor = NSSelectorFromString(@"setTintColor:");
            if (effect && tintColor && [effect respondsToSelector:setTintColor]) {
                ((void (*)(id, SEL, id))objc_msgSend)(effect, setTintColor, tintColor);
            }
            if ([effect isKindOfClass:UIVisualEffect.class]) return (UIVisualEffect *)effect;
        }
    }

    if (@available(iOS 13.0, *)) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
}

UIVisualEffect *FBTUIKit26GlassContainerEffect(CGFloat spacing) {
    if (@available(iOS 26.0, *)) {
        Class containerClass = NSClassFromString(@"UIGlassContainerEffect");
        id effect = containerClass ? [[containerClass alloc] init] : nil;
        SEL setSpacing = NSSelectorFromString(@"setSpacing:");
        if (effect && [effect respondsToSelector:setSpacing]) {
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(effect, setSpacing, spacing);
        }
        if ([effect isKindOfClass:UIVisualEffect.class]) return (UIVisualEffect *)effect;
    }
    return nil;
}

UIColor *FBTUIKit26BaseSurfaceColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? UIColor.blackColor : UIColor.whiteColor;
    }];
}

UIColor *FBTUIKit26PanelFillColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.105]
            : [UIColor colorWithWhite:1.0 alpha:0.34];
    }];
}

UIColor *FBTUIKit26SeparatorColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.075]
            : [UIColor colorWithWhite:0.0 alpha:0.06];
    }];
}

static UIColor *FBTUIKit26CellSelectedFillColor(void) {
    return [FBTUIKit26TintColor() colorWithAlphaComponent:0.16];
}

static UIColor *FBTUIKit26CellPressedFillColor(void) {
    return [UIColor.labelColor colorWithAlphaComponent:0.10];
}

static UIColor *FBTUIKit26BorderColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.12]
            : [UIColor colorWithWhite:0.0 alpha:0.08];
    }];
}

void FBTUIKit26ApplyContainerBackgroundToViewController(UIViewController *vc) {
    if (!vc || !FBTUIKit26IsAvailable()) return;
    NSInteger glassStyle = 1; // UIContainerBackgroundStyleGlass in the iOS 26 SDK.
    SEL preferred = NSSelectorFromString(@"setPreferredContainerBackgroundStyle:");
    SEL direct = NSSelectorFromString(@"setContainerBackgroundStyle:");
    if ([vc respondsToSelector:preferred]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(vc, preferred, glassStyle);
    } else if ([vc respondsToSelector:direct]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(vc, direct, glassStyle);
    }
}

void FBTUIKit26InstallNavigationTitleBubble(UIViewController *vc) {
    if (!vc || !FBTUIKit26IsAvailable()) return;
    NSString *title = vc.title ?: vc.navigationItem.title;
    if (!title.length) return;

    FBTUIKit26TitleBubbleView *bubble = nil;
    if ([vc.navigationItem.titleView isKindOfClass:FBTUIKit26TitleBubbleView.class]) {
        bubble = (FBTUIKit26TitleBubbleView *)vc.navigationItem.titleView;
    } else {
        bubble = [[FBTUIKit26TitleBubbleView alloc] initWithTitle:title];
        vc.navigationItem.titleView = bubble;
    }
    [bubble configureWithTitle:title];
}

void FBTUIKit26RefreshNavigationTitleBubble(UIViewController *vc) {
    if (!vc || !FBTUIKit26IsAvailable()) return;
    NSString *title = vc.title ?: vc.navigationItem.title;
    if (!title.length) return;
    if ([vc.navigationItem.titleView isKindOfClass:FBTUIKit26TitleBubbleView.class]) {
        [(FBTUIKit26TitleBubbleView *)vc.navigationItem.titleView configureWithTitle:title];
    } else {
        FBTUIKit26InstallNavigationTitleBubble(vc);
    }
}

void FBTConfigureNavigationChromeForGlass(UIViewController *vc) {
    if (!vc) return;
    FBTUIKit26InstallNavigationTitleBubble(vc);

    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (bar) {
        bar.translucent = YES;
        bar.backgroundColor = UIColor.clearColor;
        bar.prefersLargeTitles = NO;
        if (@available(iOS 13.0, *)) {
            UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
            [appearance configureWithTransparentBackground];
            appearance.backgroundColor = UIColor.clearColor;
            appearance.backgroundEffect = FBTUIKit26GlassEffect(NO, NO, nil);
            appearance.shadowColor = UIColor.clearColor;
            NSDictionary *titleAttrs = @{
                NSForegroundColorAttributeName: UIColor.labelColor,
                NSFontAttributeName: [UIFont systemFontOfSize:19.0 weight:UIFontWeightBold]
            };
            appearance.titleTextAttributes = titleAttrs;
            appearance.buttonAppearance.normal.titleTextAttributes = titleAttrs;
            bar.titleTextAttributes = titleAttrs;
            bar.standardAppearance = appearance;
            bar.scrollEdgeAppearance = appearance;
            bar.compactAppearance = appearance;
            if (@available(iOS 15.0, *)) bar.compactScrollEdgeAppearance = appearance;
        }
    }

    UIToolbar *toolbar = vc.navigationController.toolbar;
    if (toolbar && @available(iOS 13.0, *)) {
        UIToolbarAppearance *appearance = [UIToolbarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.backgroundEffect = FBTUIKit26GlassEffect(NO, NO, nil);
        appearance.shadowColor = UIColor.clearColor;
        toolbar.standardAppearance = appearance;
        if (@available(iOS 15.0, *)) toolbar.scrollEdgeAppearance = appearance;
        toolbar.translucent = YES;
        toolbar.backgroundColor = UIColor.clearColor;
    }

    if (vc.tabBarController.tabBar) FBTUIKit26ConfigureTabBar(vc.tabBarController.tabBar);
}

void FBTUIKit26ConfigureViewController(UIViewController *vc) {
    if (!vc) return;
    FBTUIKit26ApplyContainerBackgroundToViewController(vc);
    if (vc.isViewLoaded) {
        vc.view.backgroundColor = FBTUIKit26BaseSurfaceColor();
        vc.view.opaque = YES;
        vc.view.layer.backgroundColor = [FBTUIKit26BaseSurfaceColor() resolvedColorWithTraitCollection:vc.view.traitCollection].CGColor;
    }
    FBTConfigureNavigationChromeForGlass(vc);
    __weak UIViewController *weakVC = vc;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *strongVC = weakVC;
        if (strongVC) FBTUIKit26RefreshNavigationTitleBubble(strongVC);
    });
}

static void FBTUIKit26ConfigureScrollEdgeEffect(id edgeEffect, NSInteger style, BOOL hidden) {
    if (!edgeEffect) return;
    SEL setStyle = NSSelectorFromString(@"setStyle:");
    if ([edgeEffect respondsToSelector:setStyle]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(edgeEffect, setStyle, style);
    }
    SEL setHidden = NSSelectorFromString(@"setHidden:");
    if ([edgeEffect respondsToSelector:setHidden]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(edgeEffect, setHidden, hidden);
    }
    SEL igSetHidden = NSSelectorFromString(@"ig_setIsHidden:");
    if ([edgeEffect respondsToSelector:igSetHidden]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(edgeEffect, igSetHidden, hidden);
    }
}

void FBTUIKit26ConfigureScrollView(UIScrollView *scrollView) {
    if (!scrollView) return;
    scrollView.backgroundColor = UIColor.clearColor;
    scrollView.opaque = NO;
    if (@available(iOS 11.0, *)) scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;

    if (@available(iOS 26.0, *)) {
        SEL topSel = NSSelectorFromString(@"topEdgeEffect");
        SEL bottomSel = NSSelectorFromString(@"bottomEdgeEffect");
        if ([scrollView respondsToSelector:topSel]) {
            id edge = ((id (*)(id, SEL))objc_msgSend)(scrollView, topSel);
            FBTUIKit26ConfigureScrollEdgeEffect(edge, 0, NO);
        }
        if ([scrollView respondsToSelector:bottomSel]) {
            id edge = ((id (*)(id, SEL))objc_msgSend)(scrollView, bottomSel);
            FBTUIKit26ConfigureScrollEdgeEffect(edge, 0, NO);
        }
    }

    if ([scrollView isKindOfClass:UITableView.class]) {
        UITableView *tableView = (UITableView *)scrollView;
        tableView.backgroundView = nil;
        tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 0.0;
        if (@available(iOS 26.0, *)) {
            SEL setBackgroundEffect = NSSelectorFromString(@"setBackgroundEffect:");
            if ([tableView respondsToSelector:setBackgroundEffect]) {
                ((void (*)(id, SEL, id))objc_msgSend)(tableView, setBackgroundEffect, FBTUIKit26GlassEffect(YES, NO, nil));
            }
        }
    }
}

void FBTUIKit26ConfigureTableView(UITableView *tableView) {
    if (!tableView) return;
    FBTUIKit26ConfigureScrollView(tableView);
    tableView.backgroundColor = UIColor.clearColor;
    tableView.backgroundView = nil;
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    tableView.layoutMargins = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
}

void FBTUIKit26ConfigureCollectionView(UICollectionView *collectionView) {
    if (!collectionView) return;
    FBTUIKit26ConfigureScrollView(collectionView);
    collectionView.backgroundColor = UIColor.clearColor;
    collectionView.alwaysBounceVertical = YES;
}

void FBTUIKit26ConfigureGlassView(UIView *view, CGFloat radius, BOOL interactive) {
    if (!view) return;
    view.backgroundColor = UIColor.clearColor;
    view.layer.cornerRadius = radius;
    if ([view.layer respondsToSelector:@selector(setCornerCurve:)]) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
    FBTUIKit26EnsureGlassBackground(view, radius, interactive, NO, nil);
}

void FBTUIKit26ConfigureButton(UIButton *button) {
    if (!button) return;
    button.backgroundColor = UIColor.clearColor;
    button.layer.backgroundColor = UIColor.clearColor.CGColor;
    button.tintColor = FBTUIKit26TintColor();

    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = nil;
        if (@available(iOS 26.0, *)) {
            Class cls = UIButtonConfiguration.class;
            SEL clearGlass = NSSelectorFromString(@"clearGlassButtonConfiguration");
            SEL plainGlass = NSSelectorFromString(@"glassButtonConfiguration");
            if ([cls respondsToSelector:clearGlass]) {
                cfg = ((id (*)(id, SEL))objc_msgSend)(cls, clearGlass);
            } else if ([cls respondsToSelector:plainGlass]) {
                cfg = ((id (*)(id, SEL))objc_msgSend)(cls, plainGlass);
            }
        }
        if (!cfg) cfg = button.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
        cfg.background.backgroundColor = UIColor.clearColor;
        cfg.background.visualEffect = FBTUIKit26IsAvailable() ? FBTUIKit26GlassEffect(YES, YES, nil) : nil;
        cfg.baseForegroundColor = FBTUIKit26TintColor();
        button.configuration = cfg;
    }
}

void FBTStyleControlForGlass(UIControl *control) {
    if (!control) return;
    if ([control isKindOfClass:UIButton.class]) {
        FBTUIKit26ConfigureButton((UIButton *)control);
    } else if ([control isKindOfClass:UISegmentedControl.class]) {
        FBTUIKit26ConfigureSegmentedControl((UISegmentedControl *)control);
    } else {
        control.backgroundColor = UIColor.clearColor;
    }
}

void FBTUIKit26ConfigureSearchBar(UISearchBar *searchBar) {
    if (!searchBar) return;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.backgroundImage = UIImage.new;
    searchBar.barTintColor = UIColor.clearColor;
    searchBar.backgroundColor = UIColor.clearColor;
    searchBar.translucent = YES;

    UITextField *field = searchBar.searchTextField;
    if (!field) return;
    field.textColor = UIColor.labelColor;
    field.tintColor = FBTUIKit26TintColor();
    field.borderStyle = UITextBorderStyleNone;
    field.background = nil;
    field.disabledBackground = nil;
    field.backgroundColor = UIColor.clearColor;
    field.layer.backgroundColor = UIColor.clearColor.CGColor;
    field.layer.cornerRadius = 0.0;
    field.layer.borderWidth = 0.0;
    field.layer.masksToBounds = NO;
    field.clipsToBounds = NO;
    field.leftView.tintColor = UIColor.secondaryLabelColor;
    field.rightView.tintColor = UIColor.secondaryLabelColor;

    NSString *placeholder = field.attributedPlaceholder.string ?: field.placeholder ?: @"";
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor
    }];
}

void FBTUIKit26ConfigureSegmentedControl(UISegmentedControl *control) {
    if (!control) return;
    control.backgroundColor = UIColor.clearColor;
    control.selectedSegmentTintColor = FBTUIKit26IsAvailable() ? nil : [UIColor.labelColor colorWithAlphaComponent:0.12];
    NSDictionary *normal = @{ NSForegroundColorAttributeName: UIColor.secondaryLabelColor };
    NSDictionary *selected = @{ NSForegroundColorAttributeName: UIColor.labelColor, NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold] };
    [control setTitleTextAttributes:normal forState:UIControlStateNormal];
    [control setTitleTextAttributes:selected forState:UIControlStateSelected];
}

void FBTUIKit26ConfigureTabBar(UITabBar *tabBar) {
    if (!tabBar) return;
    tabBar.translucent = YES;
    tabBar.backgroundColor = UIColor.clearColor;
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.backgroundEffect = FBTUIKit26GlassEffect(NO, NO, nil);
        appearance.shadowColor = UIColor.clearColor;
        tabBar.standardAppearance = appearance;
        if (@available(iOS 15.0, *)) tabBar.scrollEdgeAppearance = appearance;
    }
}

void FBTUIKit26ConfigureTableCell(UITableViewCell *cell) {
    if (!cell) return;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.preservesSuperviewLayoutMargins = YES;
    cell.layoutMargins = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);

    UIView *selected = [UIView new];
    selected.backgroundColor = FBTUIKit26CellPressedFillColor();
    selected.layer.cornerRadius = 12.0;
    if ([selected.layer respondsToSelector:@selector(setCornerCurve:)]) selected.layer.cornerCurve = kCACornerCurveContinuous;
    selected.clipsToBounds = YES;
    cell.selectedBackgroundView = selected;

    if (@available(iOS 14.0, *)) {
        UIBackgroundConfiguration *bg = [UIBackgroundConfiguration listGroupedCellConfiguration];
        bg.backgroundColor = FBTUIKit26PanelFillColor();
        bg.visualEffect = nil;
        bg.strokeColor = UIColor.clearColor;
        bg.strokeWidth = 0.0;
        cell.backgroundConfiguration = bg;
        cell.backgroundView = nil;
    } else {
        FBTUIKit26EnsureGlassBackground(cell.contentView, 12.0, YES, YES, nil);
    }
}

void FBTUIKit26ApplyTableCellSelectionTint(UITableViewCell *cell, BOOL selected) {
    if (!cell) return;
    if (@available(iOS 14.0, *)) {
        UIBackgroundConfiguration *bg = cell.backgroundConfiguration ?: [UIBackgroundConfiguration listGroupedCellConfiguration];
        bg.backgroundColor = selected ? FBTUIKit26CellSelectedFillColor() : FBTUIKit26PanelFillColor();
        bg.visualEffect = nil;
        bg.strokeColor = UIColor.clearColor;
        bg.strokeWidth = 0.0;
        cell.backgroundConfiguration = bg;
    } else {
        cell.contentView.backgroundColor = selected ? FBTUIKit26CellSelectedFillColor() : UIColor.clearColor;
    }
}

void FBTStyleCollectionCellForGlass(UICollectionViewCell *cell) {
    if (!cell) return;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.selectedBackgroundView = [UIView new];
    cell.selectedBackgroundView.backgroundColor = FBTUIKit26CellPressedFillColor();
    if (FBTUIKit26IsAvailable()) {
        if (!cell.backgroundView) {
            UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:FBTUIKit26GlassEffect(NO, YES, nil)];
            glass.layer.cornerRadius = 18.0;
            if ([glass.layer respondsToSelector:@selector(setCornerCurve:)]) glass.layer.cornerCurve = kCACornerCurveContinuous;
            glass.clipsToBounds = YES;
            cell.backgroundView = glass;
        } else {
            FBTUIKit26ConfigureGlassView(cell.backgroundView, 18.0, YES);
        }
    }
}

static UIVisualEffectView *FBTUIKit26EnsureGlassBackground(UIView *view, CGFloat radius, BOOL interactive, BOOL clearStyle, UIColor *tintColor) {
    if (!view) return nil;
    UIVisualEffect *effect = FBTUIKit26GlassEffect(clearStyle, interactive, tintColor);
    if (!effect) return nil;

    if ([view isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *effectView = (UIVisualEffectView *)view;
        effectView.effect = effect;
        effectView.backgroundColor = UIColor.clearColor;
        effectView.contentView.backgroundColor = UIColor.clearColor;
        effectView.layer.cornerRadius = radius;
        if ([effectView.layer respondsToSelector:@selector(setCornerCurve:)]) effectView.layer.cornerCurve = kCACornerCurveContinuous;
        effectView.layer.masksToBounds = YES;
        effectView.clipsToBounds = YES;
        return effectView;
    }

    UIVisualEffectView *glass = (UIVisualEffectView *)[view viewWithTag:kFBTUIKit26GlassBackgroundTag];
    if (![glass isKindOfClass:UIVisualEffectView.class]) {
        glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.tag = kFBTUIKit26GlassBackgroundTag;
        glass.userInteractionEnabled = NO;
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [view insertSubview:glass atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [glass.topAnchor constraintEqualToAnchor:view.topAnchor],
            [glass.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
            [glass.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
            [glass.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        ]];
    } else {
        glass.effect = effect;
    }

    glass.backgroundColor = UIColor.clearColor;
    glass.contentView.backgroundColor = UIColor.clearColor;
    glass.layer.cornerRadius = radius;
    if ([glass.layer respondsToSelector:@selector(setCornerCurve:)]) glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
    view.backgroundColor = UIColor.clearColor;
    view.layer.cornerRadius = radius;
    if ([view.layer respondsToSelector:@selector(setCornerCurve:)]) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
    return glass;
}

@implementation FBTUIKit26GlassPanelView

- (instancetype)initWithRadius:(CGFloat)radius {
    self = [super initWithEffect:FBTUIKit26GlassEffect(NO, NO, nil)];
    if (self) {
        _sciCornerRadius = radius;
        [self applyLiquidGlassStyle];
    }
    return self;
}

- (instancetype)initWithEffect:(UIVisualEffect *)effect {
    self = [super initWithEffect:effect ?: FBTUIKit26GlassEffect(NO, NO, nil)];
    if (self) {
        _sciCornerRadius = 22.0;
        [self applyLiquidGlassStyle];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyLiquidGlassStyle];
}

- (void)setSciGlassInteractive:(BOOL)fbtGlassInteractive {
    _sciGlassInteractive = fbtGlassInteractive;
    [self applyLiquidGlassStyle];
}

- (void)setSciGlassClearStyle:(BOOL)fbtGlassClearStyle {
    _sciGlassClearStyle = fbtGlassClearStyle;
    [self applyLiquidGlassStyle];
}

- (void)setSciGlassTintColor:(UIColor *)fbtGlassTintColor {
    _sciGlassTintColor = fbtGlassTintColor;
    [self applyLiquidGlassStyle];
}

- (void)applyLiquidGlassStyle {
    self.effect = FBTUIKit26GlassEffect(self.fbtGlassClearStyle, self.fbtGlassInteractive, self.fbtGlassTintColor);
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = self.fbtGlassClearStyle ? UIColor.clearColor : FBTUIKit26PanelFillColor();
    self.layer.cornerRadius = self.fbtCornerRadius;
    if ([self.layer respondsToSelector:@selector(setCornerCurve:)]) self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.clipsToBounds = YES;
    self.layer.borderWidth = FBTUIKit26IsAvailable() ? 0.0 : 0.7;
    self.layer.borderColor = FBTUIKit26IsAvailable() ? UIColor.clearColor.CGColor : FBTUIKit26BorderColor().CGColor;
}

@end

@interface FBTUIKit26SectionHeaderView ()
@property (nonatomic, strong) FBTUIKit26GlassPanelView *panel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation FBTUIKit26SectionHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
        self.contentView.backgroundColor = UIColor.clearColor;
        _panel = [[FBTUIKit26GlassPanelView alloc] initWithRadius:16.0];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_panel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 2.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_panel.contentView addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
            [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_panel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [stack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:10.0],
            [stack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14.0],
            [stack.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-14.0],
            [stack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-10.0],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.subtitleLabel.hidden = subtitle.length == 0;
}

@end

@interface FBTUIKit26ParamCell ()
@property (nonatomic, strong) FBTUIKit26GlassPanelView *panel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@end

@implementation FBTUIKit26ParamCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectedBackgroundView = [UIView new];
        self.selectedBackgroundView.backgroundColor = FBTUIKit26CellPressedFillColor();

        _panel = [[FBTUIKit26GlassPanelView alloc] initWithRadius:18.0];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_panel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.numberOfLines = 2;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.numberOfLines = 4;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _badgeLabel = [UILabel new];
        _badgeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        _badgeLabel.textColor = UIColor.labelColor;
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.08];
        _badgeLabel.layer.cornerRadius = 10.0;
        if ([_badgeLabel.layer respondsToSelector:@selector(setCornerCurve:)]) _badgeLabel.layer.cornerCurve = kCACornerCurveContinuous;
        _badgeLabel.clipsToBounds = YES;
        _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 4.0;
        textStack.translatesAutoresizingMaskIntoConstraints = NO;

        [_panel.contentView addSubview:textStack];
        [_panel.contentView addSubview:_badgeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
            [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
            [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0],
            [_panel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],
            [textStack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:12.0],
            [textStack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14.0],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_badgeLabel.leadingAnchor constant:-10.0],
            [textStack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-12.0],
            [_badgeLabel.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-12.0],
            [_badgeLabel.centerYAnchor constraintEqualToAnchor:_panel.contentView.centerYAnchor],
            [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:48.0],
            [_badgeLabel.heightAnchor constraintEqualToConstant:22.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self configureWithTitle:@"" subtitle:@"" badge:nil emphasized:NO];
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle badge:(NSString *)badge emphasized:(BOOL)emphasized {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.badgeLabel.text = badge ?: @"";
    self.badgeLabel.hidden = badge.length == 0;
    self.titleLabel.font = emphasized ? [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] : [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.panel.fbtGlassTintColor = emphasized ? [FBTUIKit26TintColor() colorWithAlphaComponent:0.18] : nil;
    self.panel.contentView.backgroundColor = emphasized ? [FBTUIKit26TintColor() colorWithAlphaComponent:0.18] : FBTUIKit26PanelFillColor();
    self.badgeLabel.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:emphasized ? 0.12 : 0.08];
}

@end

@interface FBTUIKit26FloatingToolbar ()
@property (nonatomic, strong) UIButton *captureButton;
@end

@implementation FBTUIKit26FloatingToolbar

static UIButton *FBTUIKit26ToolbarButton(NSString *title, NSString *symbol, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.title = title;
        cfg.image = [UIImage systemImageNamed:symbol];
        cfg.imagePadding = 5.0;
        cfg.buttonSize = UIButtonConfigurationSizeSmall;
        cfg.background.backgroundColor = UIColor.clearColor;
        cfg.background.visualEffect = FBTUIKit26GlassEffect(YES, YES, nil);
        button.configuration = cfg;
    } else {
        [button setTitle:title forState:UIControlStateNormal];
    }
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (instancetype)initWithTarget:(id)target refresh:(SEL)refresh clear:(SEL)clear export:(SEL)export toggleCapture:(SEL)toggleCapture {
    self = [super initWithRadius:24.0];
    if (self) {
        self.fbtGlassClearStyle = NO;
        self.fbtGlassInteractive = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        UIButton *refreshButton = FBTUIKit26ToolbarButton(@"Refresh", @"arrow.clockwise", target, refresh);
        UIButton *exportButton = FBTUIKit26ToolbarButton(@"Export", @"square.and.arrow.up", target, export);
        UIButton *clearButton = FBTUIKit26ToolbarButton(@"Clear", @"trash", target, clear);
        _captureButton = FBTUIKit26ToolbarButton(@"Capture", @"dot.radiowaves.left.and.right", target, toggleCapture);
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[refreshButton, exportButton, clearButton, _captureButton]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionEqualSpacing;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 4.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10.0],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8.0],
        ]];
    }
    return self;
}

- (void)setCaptureEnabled:(BOOL)enabled {
    NSString *title = enabled ? @"Capture ON" : @"Capture OFF";
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = self.captureButton.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
        cfg.title = title;
        cfg.baseForegroundColor = enabled ? FBTUIKit26TintColor() : UIColor.secondaryLabelColor;
        self.captureButton.configuration = cfg;
    } else {
        [self.captureButton setTitle:title forState:UIControlStateNormal];
    }
}

@end

@interface FBTUIKit26SearchBarContainerView ()
@property (nonatomic, strong, readwrite) UISearchBar *searchBar;
@end

@implementation FBTUIKit26SearchBarContainerView

- (instancetype)initWithRadius:(CGFloat)radius {
    self = [super initWithRadius:radius];
    if (self) [self commonInit];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self commonInit];
    return self;
}

- (void)commonInit {
    self.fbtCornerRadius = 22.0;
    self.fbtGlassInteractive = YES;
    [self applyLiquidGlassStyle];
    _searchBar = [UISearchBar new];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_searchBar];
    FBTUIKit26ConfigureSearchBar(_searchBar);
    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2.0],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4.0],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4.0],
        [_searchBar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-2.0],
    ]];
}

@end
