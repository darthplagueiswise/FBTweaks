#import "FBTUIKit26LiquidGlass.h"
#import <QuartzCore/QuartzCore.h>

// These helpers are opt-in and belong only to FBTweaks' presented settings UI.
// Public API: developer.apple.com/documentation/uikit/uiglasseffect
// Bars: developer.apple.com/videos/play/wwdc2025/284/ (Navigation and toolbars).
static UIColor *FBTUIKit26TintColor(void) { return UIColor.systemBlueColor; }
static NSInteger const kFBTUIKit26GlassBackgroundTag = 0x51C126;
static NSInteger const kFBTUIKit26TitleBubbleTag = 0x51C260;

static BOOL FBTUIKit26NeedsOpaqueMaterial(void) {
    return UIAccessibilityIsReduceTransparencyEnabled() || UIAccessibilityIsDarkerSystemColorsEnabled();
}

static BOOL FBTUIKit26NeedsOpaqueMaterialForTraits(UITraitCollection *traits) {
    return FBTUIKit26NeedsOpaqueMaterial() || traits.accessibilityContrast == UIAccessibilityContrastHigh;
}

BOOL FBTUIKit26IsAvailable(void) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) return YES;
#endif
    return NO;
}

UIVisualEffect *FBTUIKit26GlassEffect(BOOL clearStyle, BOOL interactive, UIColor *tintColor) {
    // An opaque semantic surface is used instead of an effect when contrast wins.
    if (FBTUIKit26NeedsOpaqueMaterial()) return nil;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:clearStyle ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
        effect.interactive = interactive;
        effect.tintColor = tintColor;
        return effect;
    }
#endif
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
}

UIVisualEffect *FBTUIKit26GlassContainerEffect(CGFloat spacing) {
    if (FBTUIKit26NeedsOpaqueMaterial()) return nil;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIGlassContainerEffect *effect = [UIGlassContainerEffect new];
        effect.spacing = MAX(0.0, spacing);
        return effect;
    }
#endif
    return nil;
}

UIColor *FBTUIKit26BaseSurfaceColor(void) { return UIColor.systemGroupedBackgroundColor; }
UIColor *FBTUIKit26PanelFillColor(void) { return UIColor.secondarySystemGroupedBackgroundColor; }
UIColor *FBTUIKit26SeparatorColor(void) { return UIColor.separatorColor; }

static UIColor *FBTUIKit26CellSelectedFillColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        CGFloat alpha = traits.accessibilityContrast == UIAccessibilityContrastHigh ? 0.28 : 0.13;
        return [UIColor.systemBlueColor colorWithAlphaComponent:alpha];
    }];
}

static UIColor *FBTUIKit26CellPressedFillColor(void) { return UIColor.tertiarySystemFillColor; }

void FBTUIKit26ApplyContainerBackgroundToViewController(UIViewController *vc) {
    // Settings are content, not a floating presentation. Do not force a glass
    // container style (or guess selectors) on UIKit's controller hierarchy.
    if (vc.isViewLoaded) vc.view.backgroundColor = FBTUIKit26BaseSurfaceColor();
}

void FBTUIKit26InstallNavigationTitleBubble(UIViewController *vc) {
    // Preserve the entry point for existing callers; let UIKit lay out the title.
    if (vc.navigationItem.titleView.tag == kFBTUIKit26TitleBubbleTag) vc.navigationItem.titleView = nil;
}

void FBTUIKit26RefreshNavigationTitleBubble(UIViewController *vc) {
    FBTUIKit26InstallNavigationTitleBubble(vc);
}

void FBTConfigureNavigationChromeForGlass(UIViewController *vc) {
    if (!vc) return;
    FBTUIKit26InstallNavigationTitleBubble(vc);
    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (bar) {
        // Reset legacy customizations to UIKit defaults. Custom bar background
        // effects/colors suppress iOS 26's native glass and scroll-edge behavior.
        bar.standardAppearance = [UINavigationBarAppearance new];
        bar.scrollEdgeAppearance = nil;
        bar.compactAppearance = nil;
        if (@available(iOS 15.0, *)) bar.compactScrollEdgeAppearance = nil;
        bar.backgroundColor = nil;
        bar.barTintColor = nil;
        bar.titleTextAttributes = nil;
        bar.largeTitleTextAttributes = nil;
        [bar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
        bar.shadowImage = nil;
        bar.translucent = YES;
    }
    UIToolbar *toolbar = vc.navigationController.toolbar;
    if (toolbar) {
        toolbar.standardAppearance = [UIToolbarAppearance new];
        toolbar.compactAppearance = nil;
        if (@available(iOS 15.0, *)) {
            toolbar.scrollEdgeAppearance = nil;
            toolbar.compactScrollEdgeAppearance = nil;
        }
        toolbar.backgroundColor = nil;
        toolbar.barTintColor = nil;
        toolbar.translucent = YES;
    }
}

void FBTUIKit26ConfigureViewController(UIViewController *vc) {
    if (!vc) return;
    FBTUIKit26ApplyContainerBackgroundToViewController(vc);
    if (vc.isViewLoaded) vc.view.tintColor = FBTUIKit26TintColor();
    FBTConfigureNavigationChromeForGlass(vc);
}

void FBTUIKit26ConfigureScrollView(UIScrollView *scrollView) {
    if (!scrollView) return;
    scrollView.backgroundColor = FBTUIKit26BaseSurfaceColor();
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    // UIKit manages native edge effects. Do not call Facebook's private
    // ig_setIsHidden: selector or add a second background material.
}

void FBTUIKit26ConfigureTableView(UITableView *tableView) {
    if (!tableView) return;
    FBTUIKit26ConfigureScrollView(tableView);
    tableView.backgroundView = nil;
    tableView.separatorColor = FBTUIKit26SeparatorColor();
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    tableView.layoutMargins = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 60.0;
    tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    tableView.estimatedSectionHeaderHeight = 44.0;
    tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    tableView.estimatedSectionFooterHeight = 28.0;
}

void FBTUIKit26ConfigureCollectionView(UICollectionView *collectionView) {
    if (!collectionView) return;
    FBTUIKit26ConfigureScrollView(collectionView);
    collectionView.alwaysBounceVertical = YES;
}

static FBTUIKit26GlassPanelView *FBTUIKit26EnsureGlassBackground(UIView *view, CGFloat radius, BOOL interactive) {
    if (!view) return nil;
    FBTUIKit26GlassPanelView *glass = nil;
    if ([view isKindOfClass:FBTUIKit26GlassPanelView.class]) {
        glass = (FBTUIKit26GlassPanelView *)view;
    } else {
        UIView *candidate = [view viewWithTag:kFBTUIKit26GlassBackgroundTag];
        if ([candidate isKindOfClass:FBTUIKit26GlassPanelView.class]) glass = (FBTUIKit26GlassPanelView *)candidate;
        else {
            [candidate removeFromSuperview];
            glass = [[FBTUIKit26GlassPanelView alloc] initWithRadius:radius];
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
        }
    }
    glass.fbtCornerRadius = radius;
    glass.fbtGlassInteractive = interactive;
    [glass applyLiquidGlassStyle];
    return glass;
}

void FBTUIKit26ConfigureGlassView(UIView *view, CGFloat radius, BOOL interactive) {
    if (!view) return;
    if ([view isKindOfClass:UIVisualEffectView.class] && ![view isKindOfClass:FBTUIKit26GlassPanelView.class]) {
        UIVisualEffectView *effectView = (UIVisualEffectView *)view;
        effectView.effect = FBTUIKit26NeedsOpaqueMaterialForTraits(view.traitCollection) ? nil : FBTUIKit26GlassEffect(NO, interactive, nil);
        effectView.contentView.backgroundColor = FBTUIKit26NeedsOpaqueMaterialForTraits(view.traitCollection) ? FBTUIKit26PanelFillColor() : UIColor.clearColor;
    } else {
        FBTUIKit26EnsureGlassBackground(view, radius, interactive);
    }
    view.backgroundColor = UIColor.clearColor;
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
}

void FBTUIKit26ConfigureButton(UIButton *button) {
    if (!button) return;
    button.tintColor = FBTUIKit26TintColor();
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    if (@available(iOS 15.0, *)) {
        // Changing only the background preserves titles, images, actions and sizes.
        UIButtonConfiguration *configuration = button.configuration ?: [UIButtonConfiguration plainButtonConfiguration];
        UIButtonConfiguration *style = [UIButtonConfiguration tintedButtonConfiguration];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
        if (@available(iOS 26.0, *)) {
            if (!FBTUIKit26NeedsOpaqueMaterialForTraits(button.traitCollection)) style = [UIButtonConfiguration glassButtonConfiguration];
        }
#endif
        configuration.background = style.background;
        configuration.baseForegroundColor = FBTUIKit26TintColor();
        button.configuration = configuration;
    }
}

void FBTStyleControlForGlass(UIControl *control) {
    if ([control isKindOfClass:UIButton.class]) FBTUIKit26ConfigureButton((UIButton *)control);
    else if ([control isKindOfClass:UISegmentedControl.class]) FBTUIKit26ConfigureSegmentedControl((UISegmentedControl *)control);
    else control.tintColor = FBTUIKit26TintColor();
}

void FBTUIKit26ConfigureSearchBar(UISearchBar *searchBar) {
    if (!searchBar) return;
    // UISearchBar already owns a native material. Preserve it and its field.
    searchBar.tintColor = FBTUIKit26TintColor();
    searchBar.searchTextField.textColor = UIColor.labelColor;
    searchBar.searchTextField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    searchBar.searchTextField.adjustsFontForContentSizeCategory = YES;
}

void FBTUIKit26ConfigureSegmentedControl(UISegmentedControl *control) {
    if (!control) return;
    control.tintColor = FBTUIKit26TintColor();
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.labelColor} forState:UIControlStateNormal];
    [control setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.labelColor} forState:UIControlStateSelected];
}

void FBTUIKit26ConfigureTabBar(UITabBar *tabBar) {
    if (!tabBar) return;
    tabBar.standardAppearance = [UITabBarAppearance new];
    if (@available(iOS 15.0, *)) tabBar.scrollEdgeAppearance = nil;
    tabBar.backgroundColor = nil;
    tabBar.barTintColor = nil;
}

void FBTUIKit26ConfigureTableCell(UITableViewCell *cell) {
    if (!cell) return;
    cell.preservesSuperviewLayoutMargins = YES;
    cell.layoutMargins = UIEdgeInsetsMake(10.0, 16.0, 10.0, 16.0);
    cell.tintColor = FBTUIKit26TintColor();
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    cell.contentView.backgroundColor = UIColor.clearColor;
    [[cell.contentView viewWithTag:kFBTUIKit26GlassBackgroundTag] removeFromSuperview];
    if (@available(iOS 14.0, *)) {
        UIBackgroundConfiguration *background = [UIBackgroundConfiguration listGroupedCellConfiguration];
        background.backgroundColor = FBTUIKit26PanelFillColor();
        cell.backgroundConfiguration = background;
    } else {
        cell.backgroundColor = FBTUIKit26PanelFillColor();
    }
    UIView *selected = [UIView new];
    selected.backgroundColor = FBTUIKit26CellPressedFillColor();
    cell.selectedBackgroundView = selected;
}

void FBTUIKit26ApplyTableCellSelectionTint(UITableViewCell *cell, BOOL selected) {
    if (!cell) return;
    if (@available(iOS 14.0, *)) {
        UIBackgroundConfiguration *background = cell.backgroundConfiguration ?: [UIBackgroundConfiguration listGroupedCellConfiguration];
        background.backgroundColor = selected ? FBTUIKit26CellSelectedFillColor() : FBTUIKit26PanelFillColor();
        cell.backgroundConfiguration = background;
    } else cell.backgroundColor = selected ? FBTUIKit26CellSelectedFillColor() : FBTUIKit26PanelFillColor();
}

void FBTStyleCollectionCellForGlass(UICollectionViewCell *cell) {
    if (!cell) return;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    // Collection cells are content cards, not a second layer of glass controls.
    UIView *background = [UIView new];
    background.backgroundColor = FBTUIKit26PanelFillColor();
    background.layer.cornerRadius = 16.0;
    background.layer.cornerCurve = kCACornerCurveContinuous;
    cell.backgroundView = background;
    UIView *selected = [UIView new];
    selected.backgroundColor = FBTUIKit26CellPressedFillColor();
    selected.layer.cornerRadius = 16.0;
    cell.selectedBackgroundView = selected;
}

@implementation FBTUIKit26GlassPanelView

- (instancetype)initWithRadius:(CGFloat)radius {
    self = [super initWithEffect:nil];
    if (self) {
        _fbtCornerRadius = radius;
        [self fbtObserveAccessibility];
        [self applyLiquidGlassStyle];
    }
    return self;
}

- (instancetype)initWithEffect:(UIVisualEffect *)effect {
    self = [super initWithEffect:effect];
    if (self) {
        _fbtCornerRadius = 22.0;
        [self fbtObserveAccessibility];
        [self applyLiquidGlassStyle];
    }
    return self;
}

- (void)fbtObserveAccessibility {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(fbtAccessibilityChanged:) name:UIAccessibilityReduceTransparencyStatusDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(fbtAccessibilityChanged:) name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification object:nil];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)fbtAccessibilityChanged:(NSNotification *)notification { [self applyLiquidGlassStyle]; }

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyLiquidGlassStyle];
}

- (void)setFbtCornerRadius:(CGFloat)radius { _fbtCornerRadius = radius; [self applyLiquidGlassStyle]; }
- (void)setFbtGlassInteractive:(BOOL)value { _fbtGlassInteractive = value; [self applyLiquidGlassStyle]; }
- (void)setFbtGlassClearStyle:(BOOL)value { _fbtGlassClearStyle = value; [self applyLiquidGlassStyle]; }
- (void)setFbtGlassTintColor:(UIColor *)value { _fbtGlassTintColor = value; [self applyLiquidGlassStyle]; }

- (void)applyLiquidGlassStyle {
    self.effect = FBTUIKit26NeedsOpaqueMaterialForTraits(self.traitCollection) ? nil : FBTUIKit26GlassEffect(self.fbtGlassClearStyle, self.fbtGlassInteractive, self.fbtGlassTintColor);
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = self.effect ? UIColor.clearColor : FBTUIKit26PanelFillColor();
    self.layer.cornerRadius = self.fbtCornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    self.layer.borderWidth = FBTUIKit26NeedsOpaqueMaterialForTraits(self.traitCollection) ? 1.0 : 0.0;
    self.layer.borderColor = [UIColor.separatorColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}

@end

@interface FBTUIKit26SectionHeaderView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation FBTUIKit26SectionHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.numberOfLines = 0;
        _titleLabel.accessibilityTraits |= UIAccessibilityTraitHeader;
        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;
        _subtitleLabel.numberOfLines = 0;
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16.0],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8.0],
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
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@end

@implementation FBTUIKit26ParamCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        FBTUIKit26ConfigureTableCell(self);
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _titleLabel.textColor = UIColor.labelColor;
        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _badgeLabel = [UILabel new];
        _badgeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _badgeLabel.textColor = UIColor.systemBlueColor;
        for (UILabel *label in @[_titleLabel, _subtitleLabel, _badgeLabel]) {
            label.adjustsFontForContentSizeCategory = YES;
            label.numberOfLines = 0;
        }
        // A vertical status line expands naturally for long QE values and the
        // largest accessibility sizes instead of squeezing a fixed-width badge.
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel, _badgeLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
        ]];
        self.isAccessibilityElement = YES;
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
    self.subtitleLabel.hidden = subtitle.length == 0;
    self.badgeLabel.text = badge ?: @"";
    self.badgeLabel.hidden = badge.length == 0;
    self.titleLabel.font = [UIFont preferredFontForTextStyle:emphasized ? UIFontTextStyleHeadline : UIFontTextStyleBody];
    self.accessibilityLabel = title;
    self.accessibilityValue = [@[subtitle ?: @"", badge ?: @""] componentsJoinedByString:@". "];
}

@end

@interface FBTUIKit26FloatingToolbar ()
@property (nonatomic, strong) UIButton *captureButton;
@property (nonatomic, strong) UIStackView *buttonStack;
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
        // The enclosing toolbar supplies the material; do not stack glass.
        button.configuration = cfg;
    } else {
        [button setTitle:title forState:UIControlStateNormal];
    }
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
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
        self.buttonStack = stack;
        stack.axis = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory) ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
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

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.buttonStack.axis = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory) ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
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

- (void)applyLiquidGlassStyle {
    // UISearchBar has its own native field material; this is only a layout host.
    self.effect = nil;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.layer.borderWidth = 0.0;
}

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

void FBTUIKit26ConfigureSearchNavigationItem(UINavigationItem *navigationItem) {
    if (!navigationItem) return;
    UISearchBar *searchBar = navigationItem.searchController.searchBar;
    if (searchBar) FBTUIKit26ConfigureSearchBar(searchBar);
}
