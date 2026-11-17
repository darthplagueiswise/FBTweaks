#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

BOOL FBTUIKit26IsAvailable(void);
void FBTUIKit26ConfigureViewController(UIViewController *vc);
void FBTConfigureNavigationChromeForGlass(UIViewController *vc);
UIView *FBTUIKit26CreateOverviewHeader(CGFloat width);
// Call after table layout and content-size-category changes.
void FBTUIKit26UpdateTableHeaderLayout(UITableView *tableView);
void FBTUIKit26ConfigureScrollView(UIScrollView *scrollView);
void FBTUIKit26ConfigureTableView(UITableView *tableView);
void FBTUIKit26ConfigureTableCell(UITableViewCell *cell);
void FBTUIKit26ApplyTableCellSelectionTint(UITableViewCell *cell, BOOL selected);
void FBTUIKit26ConfigureSearchBar(UISearchBar *searchBar);
void FBTUIKit26ConfigureSearchNavigationItem(UINavigationItem *navigationItem);
void FBTUIKit26ConfigureSegmentedControl(UISegmentedControl *control);

NS_ASSUME_NONNULL_END
