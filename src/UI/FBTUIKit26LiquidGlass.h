#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

BOOL FBTUIKit26IsAvailable(void);
UIVisualEffect *_Nullable FBTUIKit26GlassEffect(BOOL clearStyle, BOOL interactive, UIColor *_Nullable tintColor);
UIVisualEffect *_Nullable FBTUIKit26GlassContainerEffect(CGFloat spacing);
UIColor *FBTUIKit26BaseSurfaceColor(void);
UIColor *FBTUIKit26PanelFillColor(void);
UIColor *FBTUIKit26SeparatorColor(void);

void FBTUIKit26ApplyContainerBackgroundToViewController(UIViewController *vc);
void FBTUIKit26ConfigureViewController(UIViewController *vc);
void FBTConfigureNavigationChromeForGlass(UIViewController *vc);
void FBTUIKit26InstallNavigationTitleBubble(UIViewController *vc);
void FBTUIKit26RefreshNavigationTitleBubble(UIViewController *vc);
void FBTUIKit26ConfigureScrollView(UIScrollView *scrollView);
void FBTUIKit26ConfigureTableView(UITableView *tableView);
void FBTUIKit26ConfigureCollectionView(UICollectionView *collectionView);
void FBTUIKit26ConfigureTableCell(UITableViewCell *cell);
void FBTUIKit26ApplyTableCellSelectionTint(UITableViewCell *cell, BOOL selected);
void FBTStyleCollectionCellForGlass(UICollectionViewCell *cell);
void FBTUIKit26ConfigureGlassView(UIView *view, CGFloat radius, BOOL interactive);
void FBTUIKit26ConfigureButton(UIButton *button);
void FBTUIKit26ConfigureSearchBar(UISearchBar *searchBar);
void FBTUIKit26ConfigureSearchNavigationItem(UINavigationItem *navigationItem);
void FBTUIKit26ConfigureSegmentedControl(UISegmentedControl *control);
void FBTUIKit26ConfigureTabBar(UITabBar *tabBar);
void FBTStyleControlForGlass(UIControl *control);

@interface FBTUIKit26GlassPanelView : UIVisualEffectView
@property (nonatomic, assign) CGFloat fbtCornerRadius;
@property (nonatomic, assign) BOOL fbtGlassInteractive;
@property (nonatomic, assign) BOOL fbtGlassClearStyle;
@property (nonatomic, strong, nullable) UIColor *fbtGlassTintColor;
- (instancetype)initWithRadius:(CGFloat)radius;
- (void)applyLiquidGlassStyle;
@end

@interface FBTUIKit26SectionHeaderView : UITableViewHeaderFooterView
- (void)configureWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle;
@end

@interface FBTUIKit26ParamCell : UITableViewCell
- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle badge:(nullable NSString *)badge emphasized:(BOOL)emphasized;
@end

@interface FBTUIKit26FloatingToolbar : FBTUIKit26GlassPanelView
@end

@interface FBTUIKit26SearchBarContainerView : FBTUIKit26GlassPanelView
@property (nonatomic, strong, readonly) UISearchBar *searchBar;
@end

NS_ASSUME_NONNULL_END
