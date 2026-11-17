#import "FBTStyledTableViewController.h"
#import "FBTUIKit26LiquidGlass.h"

@implementation FBTStyledTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    FBTUIKit26ConfigureViewController(self);
    FBTUIKit26ConfigureTableView(self.tableView);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60.0;
    self.definesPresentationContext = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    FBTConfigureNavigationChromeForGlass(self);
    FBTUIKit26ConfigureSearchNavigationItem(self.navigationItem);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    FBTUIKit26UpdateTableHeaderLayout(self.tableView);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.isViewLoaded && ![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) {
        FBTUIKit26UpdateTableHeaderLayout(self.tableView);
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    FBTUIKit26ConfigureTableCell(cell);
}

@end
