#import "FBGRBoolRuntimeBrowserVC.h"
#import "FBGRMenuTheme.h"
#import "../FBGramPrefix.h"

@interface FBGRBoolRuntimeBrowserVC ()
@property(nonatomic, assign) FBGRBoolRuntimeImageKind imageKind;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) UISegmentedControl *filter;
@property(nonatomic, strong) NSArray<FBGRBoolRuntimeCandidate *> *allItems;
@property(nonatomic, strong) NSArray<FBGRBoolRuntimeCandidate *> *visible;
@end

@implementation FBGRBoolRuntimeBrowserVC

- (instancetype)initWithImageKind:(FBGRBoolRuntimeImageKind)kind {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _imageKind = kind;
        self.title = FBGRBoolRuntimeImageTitle(kind);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    FBGRApplyTable(self.tableView, self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 62;

    _filter = [[UISegmentedControl alloc] initWithItems:@[@"Todos", @"Overrides"]];
    _filter.selectedSegmentIndex = 0;
    [_filter addTarget:self action:@selector(reloadVisible) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _filter;

    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchBar.placeholder = @"Buscar classe/seletor BOOL patchável";
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshScan)];
    [self refreshScan];
}

- (void)refreshScan {
    self.allItems = FBGRBoolRuntimeCandidates(self.imageKind, YES);
    [self reloadVisible];
}

- (void)reloadVisible {
    NSArray<FBGRBoolRuntimeCandidate *> *base = self.allItems ?: @[];
    if (self.filter.selectedSegmentIndex == 1) {
        base = [base filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FBGRBoolRuntimeCandidate *c, NSDictionary *_) {
            return c.overrideSet;
        }]];
    }
    NSString *q = self.search.isActive ? self.search.searchBar.text.lowercaseString : nil;
    if (q.length) {
        base = [base filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FBGRBoolRuntimeCandidate *c, NSDictionary *_) {
            return [c.className.lowercaseString containsString:q] || [c.selectorName.lowercaseString containsString:q] || [c.stableKey.lowercaseString containsString:q];
        }]];
    }
    self.visible = base;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reloadVisible]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)self.visible.count : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"BOOL getters patcháveis encontrados no runtime ObjC" : @"Ações";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return [NSString stringWithFormat:@"%lu visíveis / %lu encontrados · overrides=%lu · toque em uma row para Force YES/NO/Clear",
            (unsigned long)self.visible.count, (unsigned long)self.allItems.count,
            (unsigned long)FBGRBoolRuntimeOverrideCountForImageKind(self.imageKind)];
    }
    return @"Scanner real: class_getImageName filtra Facebook.app/Facebook ou FBSharedFramework.framework; só métodos sem argumentos que retornam BOOL/char são listados.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"boolrt"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"boolrt"];
    FBGRApplyCell(c, ip.row % 8, nil);
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (ip.section == 1) {
        if (ip.row == 0) {
            c.imageView.image = FBGRSymbol(@"arrow.clockwise", UIColor.systemCyanColor);
            c.textLabel.text = @"Revarrer imagem agora";
            c.detailTextLabel.text = FBGRBoolRuntimeDiagnostic(self.imageKind);
        } else {
            c.imageView.image = FBGRSymbol(@"trash.fill", UIColor.systemRedColor);
            c.textLabel.text = @"Limpar overrides desta imagem";
            c.textLabel.textColor = UIColor.systemRedColor;
            c.detailTextLabel.text = @"Não remove hooks já instalados; só volta ao original";
        }
        return c;
    }

    FBGRBoolRuntimeCandidate *it = self.visible[(NSUInteger)ip.row];
    c.imageView.image = FBGRSymbol(it.classMethod ? @"plus.circle" : @"minus.circle", it.overrideSet ? UIColor.systemOrangeColor : UIColor.systemBlueColor);
    c.textLabel.text = it.displayTitle;
    c.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    c.detailTextLabel.text = it.displaySubtitle;
    c.detailTextLabel.textColor = it.overrideSet ? UIColor.systemOrangeColor : FBGRSub();
    c.accessoryType = it.overrideSet ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) {
        if (ip.row == 0) [self refreshScan];
        else { FBGRBoolRuntimeClearAllForImageKind(self.imageKind); [self refreshScan]; }
        return;
    }

    FBGRBoolRuntimeCandidate *it = self.visible[(NSUInteger)ip.row];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:it.displayTitle message:it.stableKey preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force YES" style:UIAlertActionStyleDefault handler:^(id _){ FBGRBoolRuntimeSetOverride(it, YES); [self refreshScan]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force NO" style:UIAlertActionStyleDefault handler:^(id _){ FBGRBoolRuntimeSetOverride(it, NO); [self refreshScan]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Instalar hook sem override" style:UIAlertActionStyleDefault handler:^(id _){ NSError *e=nil; FBGRBoolRuntimeInstallHook(it, &e); [self refreshScan]; }]];
    if (it.overrideSet) [a addAction:[UIAlertAction actionWithTitle:@"Clear override" style:UIAlertActionStyleDestructive handler:^(id _){ FBGRBoolRuntimeClearOverride(it); [self refreshScan]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = [tv cellForRowAtIndexPath:ip];
    [self presentViewController:a animated:YES completion:nil];
}

@end
