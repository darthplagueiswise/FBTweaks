#import "FBTUIKit26LiquidGlass.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static UIColor *FBTUIKit26TintColor(void) { return UIColor.systemBlueColor; }

BOOL FBTUIKit26IsAvailable(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

static UIColor *FBTUIKit26CellSelectedFillColor(void) {
    return [FBTUIKit26TintColor() colorWithAlphaComponent:0.16];
}

static UIColor *FBTUIKit26CellPressedFillColor(void) {
    return [UIColor.labelColor colorWithAlphaComponent:0.10];
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
        UIView *panel = [UIView new];
        panel.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        panel.translatesAutoresizingMaskIntoConstraints = NO;
        panel.layer.cornerRadius = 24.0;
        panel.clipsToBounds = YES;
        panel.userInteractionEnabled = NO;
        [self addSubview:panel];

        _headingLabel = [UILabel new];
        _headingLabel.text = @"Configurações e diagnóstico";
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
        [panel addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kFBTOverviewHorizontalMargin],
            [panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kFBTOverviewHorizontalMargin],
            [panel.topAnchor constraintEqualToAnchor:self.topAnchor constant:kFBTOverviewVerticalMargin],
            [panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-kFBTOverviewVerticalMargin],
            [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:kFBTOverviewContentInset],
            [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-kFBTOverviewContentInset],
            [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:kFBTOverviewContentInset],
            [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-kFBTOverviewContentInset]
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
    CGSize size;
    if ([header isKindOfClass:FBTUIKit26OverviewHeaderView.class]) {
        size = [header sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    } else {
        size = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                    withHorizontalFittingPriority:UILayoutPriorityRequired
                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        if (size.height <= 0.0) size = [header sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    }
    if (!isfinite(size.height) || size.height <= 0.0) return;
    CGRect frame = header.frame;
    frame.size = CGSizeMake(width, ceil(size.height));
    if (!CGRectEqualToRect(frame, header.frame)) {
        header.frame = frame;
        tableView.tableHeaderView = header;
    }
}

void FBTUIKit26ConfigureScrollView(UIScrollView *scrollView) {
    if (!scrollView) return;
    if (@available(iOS 11.0, *)) scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;

    if ([scrollView isKindOfClass:UITableView.class]) {
        UITableView *tableView = (UITableView *)scrollView;
        tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
        tableView.opaque = YES;
        tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 0.0;
    }
}

void FBTUIKit26ConfigureTableView(UITableView *tableView) {
    if (!tableView) return;
    FBTUIKit26ConfigureScrollView(tableView);
    tableView.layoutMargins = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
}

void FBTUIKit26ConfigureSearchBar(UISearchBar *searchBar) {
    if (!searchBar) return;
    searchBar.tintColor = FBTUIKit26TintColor();
    searchBar.searchTextField.textColor = UIColor.labelColor;
    searchBar.searchTextField.tintColor = FBTUIKit26TintColor();
}

void FBTUIKit26ConfigureSegmentedControl(UISegmentedControl *control) {
    if (!control) return;
    control.tintColor = FBTUIKit26TintColor();
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

void FBTUIKit26ConfigureSearchNavigationItem(UINavigationItem *navigationItem) {
    if (!navigationItem) return;
    UISearchBar *searchBar = navigationItem.searchController.searchBar;
    if (!searchBar) return;
    navigationItem.hidesSearchBarWhenScrolling = YES;
    if (@available(iOS 26.0, *)) {
        navigationItem.searchBarPlacementAllowsToolbarIntegration = NO;
        navigationItem.preferredSearchBarPlacement = UINavigationItemSearchBarPlacementIntegratedButton;
    }
    FBTUIKit26ConfigureSearchBar(searchBar);
}
