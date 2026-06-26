#import "FBTBaseSettingsListViewController.h"
#import "../UI/FBTUIKit26LiquidGlass.h"
#import "../FBTUtils.h"
#import "FBTBrowserCompat.h"

static NSString *const kFBTBaseCell = @"FBTBaseCell";
static NSString *const kFBTBaseCustomCell = @"FBTBaseCustomCell";

@implementation FBTBaseSettingsRow

+ (instancetype)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle action:(void(^)(UIViewController *vc))action {
	FBTBaseSettingsRow *r = [FBTBaseSettingsRow new];
	r.title = title ?: @"";
	r.subtitle = subtitle;
	r.action = action;
	r.style = FBTBaseSettingsRowStyleNormal;
	r.accessoryType = action ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	return r;
}

+ (instancetype)destructiveRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle action:(void(^)(UIViewController *vc))action {
	FBTBaseSettingsRow *r = [self rowWithTitle:title subtitle:subtitle action:action];
	r.style = FBTBaseSettingsRowStyleDestructive;
	r.titleColor = UIColor.systemRedColor;
	r.accessoryType = UITableViewCellAccessoryNone;
	return r;
}

+ (instancetype)switchRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle value:(BOOL(^)(void))value action:(void(^)(BOOL enabled, UIViewController *vc))action {
	FBTBaseSettingsRow *r = [FBTBaseSettingsRow new];
	r.title = title ?: @"";
	r.subtitle = subtitle;
	r.style = FBTBaseSettingsRowStyleSwitch;
	r.switchValue = value;
	r.switchAction = action;
	return r;
}

+ (instancetype)customRowWithHeight:(CGFloat)height provider:(UITableViewCell *(^)(UITableView *tableView, NSIndexPath *indexPath))provider {
	FBTBaseSettingsRow *r = [FBTBaseSettingsRow new];
	r.style = FBTBaseSettingsRowStyleCustom;
	r.customHeight = height;
	r.customCellProvider = provider;
	return r;
}

@end

@implementation FBTBaseSettingsSection

+ (instancetype)sectionWithHeader:(NSString *)header footer:(NSString *)footer rows:(NSArray<FBTBaseSettingsRow *> *)rows {
	FBTBaseSettingsSection *s = [FBTBaseSettingsSection new];
	s.header = header;
	s.footer = footer;
	s.rows = rows ?: @[];
	return s;
}

@end

@interface FBTBaseSettingsListViewController ()
@property (nonatomic, strong, readwrite) UITableView *tableView;
@end

@implementation FBTBaseSettingsListViewController

- (instancetype)initWithTitle:(NSString *)title {
	if ((self = [super init])) {
		self.title = title;
		_sections = @[];
		_reduceTopInset = YES;
	}
	return self;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	FBTUIKit26ConfigureViewController(self);
	FBTUIKit26InstallNavigationTitleBubble(self);

	_tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_tableView.dataSource = self;
	_tableView.delegate = self;
	FBTUIKit26ConfigureTableView(_tableView);
	_tableView.rowHeight = UITableViewAutomaticDimension;
	_tableView.estimatedRowHeight = 52.0;
	_tableView.contentInset = UIEdgeInsetsZero;
	_tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
	if (@available(iOS 11.0, *)) _tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
	_tableView.translatesAutoresizingMaskIntoConstraints = NO;
	[_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kFBTBaseCell];
	[_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kFBTBaseCustomCell];
	[self.view addSubview:_tableView];

	[NSLayoutConstraint activateConstraints:@[
		[_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
	]];

	[self reloadSettings];
}

- (void)reloadSettings {
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	FBTConfigureNavigationChromeForGlass(self);
	FBTUIKit26RefreshNavigationTitleBubble(self);
}

#pragma mark - Helpers

- (FBTBaseSettingsRow *)rowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.sections.count) return nil;

	NSArray *rows = self.sections[indexPath.section].rows;
	if (indexPath.row >= (NSInteger)rows.count) return nil;

	return rows[indexPath.row];
}

- (void)switchChanged:(UISwitch *)sender {
	NSIndexPath *indexPath = objc_getAssociatedObject(sender, @selector(switchChanged:));
	FBTBaseSettingsRow *row = indexPath ? [self rowAtIndexPath:indexPath] : nil;
	if (row.switchAction) row.switchAction(sender.isOn, self);
}

- (UITableViewCell *)configuredCellForRow:(FBTBaseSettingsRow *)row tableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFBTBaseCell forIndexPath:indexPath];
	FBTUIKit26ConfigureTableCell(cell);
	cell.accessoryView = nil;
	cell.accessoryType = row.accessoryType;
	cell.selectionStyle = row.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	cell.contentView.alpha = 1.0;

	UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
	cfg.text = row.dynamicTitle ? row.dynamicTitle() : row.title;
	cfg.secondaryText = row.dynamicSubtitle ? row.dynamicSubtitle() : row.subtitle;
	cfg.textProperties.color = row.titleColor ?: (row.style == FBTBaseSettingsRowStyleDestructive ? UIColor.systemRedColor : UIColor.labelColor);
	cfg.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	cfg.secondaryTextProperties.color = UIColor.secondaryLabelColor;
	cfg.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	cfg.textToSecondaryTextVerticalPadding = 3.5;
	cfg.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10.0, 16.0, 10.0, 16.0);

	if (row.icon) {
		cfg.image = row.icon;
		cfg.imageToTextPadding = 14.0;
	}

	if (row.accessoryProvider) {
		cell.accessoryView = row.accessoryProvider();
		cell.accessoryType = UITableViewCellAccessoryNone;
	}

	if (row.style == FBTBaseSettingsRowStyleSwitch) {
		UISwitch *sw = [UISwitch new];
		sw.on = row.switchValue ? row.switchValue() : NO;
		sw.onTintColor = [FBTUtils FBTColor_Primary];
		objc_setAssociatedObject(sw, @selector(switchChanged:), indexPath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}

	cell.contentConfiguration = cfg;
	return cell;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
	return self.sections.count;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section < (NSInteger)self.sections.count ? self.sections[section].rows.count : 0;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section < (NSInteger)self.sections.count ? self.sections[section].header : nil;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return section < (NSInteger)self.sections.count ? self.sections[section].footer : nil;
}

- (CGFloat)tableView:(__unused UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	FBTBaseSettingsRow *row = [self rowAtIndexPath:indexPath];
	return row.style == FBTBaseSettingsRowStyleCustom && row.customHeight > 0 ? row.customHeight : UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	FBTBaseSettingsRow *row = [self rowAtIndexPath:indexPath];
	if (!row) return [tableView dequeueReusableCellWithIdentifier:kFBTBaseCell forIndexPath:indexPath];

	if (row.style == FBTBaseSettingsRowStyleCustom && row.customCellProvider) {
		return row.customCellProvider(tableView, indexPath);
	}

	return [self configuredCellForRow:row tableView:tableView indexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	FBTBaseSettingsRow *row = [self rowAtIndexPath:indexPath];

	if (row.action) row.action(self);
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
