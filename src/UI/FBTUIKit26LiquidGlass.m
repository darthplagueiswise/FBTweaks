#import "FBTUIKit26LiquidGlass.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <math.h>

static UIColor *FBTUIKit26TintColor(void) { return [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0]; }

static NSInteger const kFBTUIKit26GlassBackgroundTag = 0x51C126;

static UIColor *FBTUIKit26BorderColor(void);
static UIVisualEffectView *FBTUIKit26EnsureGlassBackground(UIView *view, CGFloat radius, BOOL interactive, BOOL clearStyle, UIColor *tintColor);

BOOL FBTUIKit26IsAvailable(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

UIVisualEffect *FBTUIKit26GlassEffect(BOOL clearStyle, BOOL interactive, UIColor *tintColor) {
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:clearStyle ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
        effect.interactive = interactive;
        effect.tintColor = tintColor;
        return effect;
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

void FBTConfigureNavigationChromeForGlass(UIViewController *vc) {
    if (!vc) return;
    if (@available(iOS 13.0, *)) {
        // Scope the system appearance to this item; the host owns the shared bars.
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithDefaultBackground];
        UINavigationItem *item = vc.navigationItem;
        item.standardAppearance = appearance;
        item.scrollEdgeAppearance = appearance;
        item.compactAppearance = appearance;
        if (@available(iOS 15.0, *)) item.compactScrollEdgeAppearance = appearance;
    }
}

void FBTUIKit26ConfigureViewController(UIViewController *vc) {
    if (!vc) return;
    if (vc.isViewLoaded) {
        vc.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
        vc.view.opaque = YES;
    }
    FBTConfigureNavigationChromeForGlass(vc);
}

static CGFloat const kFBTOverviewHorizontalMargin = 16.0;
static CGFloat const kFBTOverviewVerticalMargin = 12.0;
static CGFloat const kFBTOverviewContentInset = 18.0;
static CGFloat const kFBTOverviewTextSpacing = 6.0;

@interface FBTUIKit26OverviewHeaderView : UIView
@property (nonatomic, strong) UILabel *headingLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@end

@implementation FBTUIKit26OverviewHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIVisualEffectView *panel = [[UIVisualEffectView alloc] initWithEffect:FBTUIKit26GlassEffect(NO, NO, nil)];
        panel.translatesAutoresizingMaskIntoConstraints = NO;
        panel.layer.cornerRadius = 24.0;
        panel.clipsToBounds = YES;
        panel.userInteractionEnabled = NO;
        [self addSubview:panel];

        _headingLabel = [UILabel new];
        _headingLabel.text = @"FBTweak";
        _headingLabel.textColor = UIColor.labelColor;
        _headingLabel.numberOfLines = 0;
        _headingLabel.adjustsFontForContentSizeCategory = YES;
        _captionLabel = [UILabel new];
        _captionLabel.text = @"Acessos nativos, flags locais e diagnósticos organizados por área.";
        _captionLabel.textColor = UIColor.secondaryLabelColor;
        _captionLabel.numberOfLines = 0;
        _captionLabel.adjustsFontForContentSizeCategory = YES;
        [self updateFonts];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_headingLabel, _captionLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = kFBTOverviewTextSpacing;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [panel.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kFBTOverviewHorizontalMargin],
            [panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kFBTOverviewHorizontalMargin],
            [panel.topAnchor constraintEqualToAnchor:self.topAnchor constant:kFBTOverviewVerticalMargin],
            [panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-kFBTOverviewVerticalMargin],
            [stack.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:kFBTOverviewContentInset],
            [stack.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-kFBTOverviewContentInset],
            [stack.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:kFBTOverviewContentInset],
            [stack.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor constant:-kFBTOverviewContentInset]
        ]];
    }
    return self;
}

- (void)updateFonts {
    UIFont *headingFont = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2 compatibleWithTraitCollection:self.traitCollection];
    UIFont *captionFont = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline compatibleWithTraitCollection:self.traitCollection];
    if (![self.headingLabel.font isEqual:headingFont]) self.headingLabel.font = headingFont;
    if (![self.captionLabel.font isEqual:captionFont]) self.captionLabel.font = captionFont;
}

- (CGSize)sizeThatFits:(CGSize)size {
    [self updateFonts];
    CGFloat textWidth = MAX(1.0, size.width - 2.0 * (kFBTOverviewHorizontalMargin + kFBTOverviewContentInset));
    CGSize textBounds = CGSizeMake(textWidth, CGFLOAT_MAX);
    CGFloat textHeight = [self.headingLabel sizeThatFits:textBounds].height
        + kFBTOverviewTextSpacing + [self.captionLabel sizeThatFits:textBounds].height;
    return CGSizeMake(size.width, ceil(textHeight + 2.0 * (kFBTOverviewVerticalMargin + kFBTOverviewContentInset)));
}

@end

UIView *FBTUIKit26CreateOverviewHeader(CGFloat width) {
    FBTUIKit26OverviewHeaderView *header = [[FBTUIKit26OverviewHeaderView alloc] initWithFrame:CGRectMake(0.0, 0.0, MAX(0.0, width), 0.0)];
    if (width > 0.0) header.frame = (CGRect){CGPointZero, [header sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)]};
    return header;
}

void FBTUIKit26UpdateTableHeaderLayout(UITableView *tableView) {
    UIView *header = tableView.tableHeaderView;
    CGFloat width = tableView.bounds.size.width;
    if (!header || width <= 0.0) return;
    CGSize size = [header sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGRect frame = header.frame;
    frame.size = CGSizeMake(width, ceil(size.height));
    if (!CGRectEqualToRect(frame, header.frame)) {
        header.frame = frame;
        tableView.tableHeaderView = header;
    }
}

void FBTUIKit26ConfigureScrollView(UIScrollView *scrollView) {
    if (!scrollView) return;
    scrollView.backgroundColor = UIColor.clearColor;
    scrollView.opaque = NO;
    if (@available(iOS 11.0, *)) scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;

    if ([scrollView isKindOfClass:UITableView.class]) {
        UITableView *tableView = (UITableView *)scrollView;
        tableView.backgroundView = nil;
        tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 0.0;
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

static UIBackgroundConfiguration *FBTUIKit26TableCellBackground(UITableViewCell *cell, UICellConfigurationState *state, BOOL selected) API_AVAILABLE(ios(14.0)) {
    UIBackgroundConfiguration *background;
    if (@available(iOS 16.0, *)) background = [cell defaultBackgroundConfiguration];
    else background = [UIBackgroundConfiguration listGroupedCellConfiguration];
    background = [background updatedConfigurationForState:state];
    background.backgroundColor = selected || state.selected ? FBTUIKit26CellSelectedFillColor()
        : state.highlighted ? FBTUIKit26CellPressedFillColor() : UIColor.secondarySystemGroupedBackgroundColor;
    background.backgroundColorTransformer = nil;
    background.visualEffect = nil;
    return background;
}

void FBTUIKit26ConfigureTableCell(UITableViewCell *cell) {
    if (!cell) return;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.preservesSuperviewLayoutMargins = YES;
    cell.layoutMargins = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);

    if (@available(iOS 14.0, *)) {
        cell.backgroundConfiguration = FBTUIKit26TableCellBackground(cell, cell.configurationState, cell.isSelected);
        if (@available(iOS 15.0, *)) {
            cell.automaticallyUpdatesBackgroundConfiguration = NO;
            cell.configurationUpdateHandler = ^(UITableViewCell *updatedCell, UICellConfigurationState *state) {
                updatedCell.backgroundConfiguration = FBTUIKit26TableCellBackground(updatedCell, state, state.selected);
            };
        }
    } else {
        cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        UIView *selected = [UIView new];
        selected.backgroundColor = FBTUIKit26CellPressedFillColor();
        cell.selectedBackgroundView = selected;
    }
}

void FBTUIKit26ApplyTableCellSelectionTint(UITableViewCell *cell, BOOL selected) {
    if (!cell) return;
    if (@available(iOS 14.0, *)) {
        cell.backgroundConfiguration = FBTUIKit26TableCellBackground(cell, cell.configurationState, selected);
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
        _fbtCornerRadius = radius;
        [self applyLiquidGlassStyle];
    }
    return self;
}

- (instancetype)initWithEffect:(UIVisualEffect *)effect {
    self = [super initWithEffect:effect ?: FBTUIKit26GlassEffect(NO, NO, nil)];
    if (self) {
        _fbtCornerRadius = 22.0;
        [self applyLiquidGlassStyle];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyLiquidGlassStyle];
}

- (void)setFbtGlassInteractive:(BOOL)fbtGlassInteractive {
    _fbtGlassInteractive = fbtGlassInteractive;
    [self applyLiquidGlassStyle];
}

- (void)setFbtGlassClearStyle:(BOOL)fbtGlassClearStyle {
    _fbtGlassClearStyle = fbtGlassClearStyle;
    [self applyLiquidGlassStyle];
}

- (void)setFbtGlassTintColor:(UIColor *)fbtGlassTintColor {
    _fbtGlassTintColor = fbtGlassTintColor;
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

void FBTUIKit26ConfigureSearchNavigationItem(UINavigationItem *navigationItem) {
    if (!navigationItem) return;
    UISearchBar *searchBar = navigationItem.searchController.searchBar;
    if (searchBar) FBTUIKit26ConfigureSearchBar(searchBar);
}
