#import "FBTHookAuditViewController.h"
#import "../Runtime/FBTRuntimeBoolBrowser.h"
#import "../Runtime/FBTMCNativeSessionProbes.h"

@interface FBTHookAuditViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *allHooks;
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleHooks;
@property (nonatomic, strong) UIView *filterContainer;
@property (nonatomic, strong) NSArray<UIButton *> *filterButtons;
@property (nonatomic, assign) NSInteger selectedFilter;
@end

@implementation FBTHookAuditViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Auditoria de Hooks";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 114;
    self.selectedFilter = 0;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
        target:self action:@selector(reloadAudit)];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    [self buildGlassFilters];
    [self reloadAudit];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadAudit];
}
- (void)buildGlassFilters {
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,80)];
    host.backgroundColor = [UIColor clearColor];
    UIVisualEffectView *container;
    if (@available(iOS 26.0, *)) {
        UIGlassContainerEffect *effect = [UIGlassContainerEffect new];
        effect.spacing = 9;
        container = [[UIVisualEffectView alloc] initWithEffect:effect];
    } else {
        container = [[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    }
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:6],
        [container.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-6],
        [container.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
        [container.heightAnchor constraintEqualToConstant:59]
    ]];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsHorizontalScrollIndicator = NO;
    [container.contentView addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:container.contentView.leadingAnchor constant:6],
        [scroll.trailingAnchor constraintEqualToAnchor:container.contentView.trailingAnchor constant:-6],
        [scroll.topAnchor constraintEqualToAnchor:container.contentView.topAnchor constant:5],
        [scroll.bottomAnchor constraintEqualToAnchor:container.contentView.bottomAnchor constant:-5]
    ]];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 6;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]
    ]];
    NSArray<NSString *> *titles = @[@"Todos", @"Executados", @"Registrados", @"Pendentes", @"Recusados"];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSInteger i=0;i<(NSInteger)titles.count;i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = i;
        button.accessibilityIdentifier = [@"fbt.hookaudit." stringByAppendingString:@[@"all",@"invoked",@"registered",@"pending",@"rejected"][i]];
        [button setTitle:titles[i] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        [button addTarget:self action:@selector(changeFilter:) forControlEvents:UIControlEventTouchUpInside];
        // Each element is an independent glass surface inside the shared
        // container. UIKit handles the merging / morphing during animations.
        UIVisualEffectView *glass;
        if (@available(iOS 26.0, *)) {
            UIGlassEffect *effect = [[UIGlassEffect alloc] initWithStyle:UIGlassEffectStyleRegular];
            effect.interactive = YES;
            glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        } else {
            glass = [[UIVisualEffectView alloc] initWithEffect:
                [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        }
        glass.layer.cornerRadius = 19;
        glass.clipsToBounds = YES;
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [stack addArrangedSubview:glass];
        [glass.contentView addSubview:button];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [glass.heightAnchor constraintEqualToConstant:42],
            [button.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:10],
            [button.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-10],
            [button.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor],
            [button.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor]
        ]];
        [buttons addObject:button];
    }
    self.filterButtons = buttons;
    self.filterContainer = host;
    self.tableView.tableHeaderView = host;
    [self updateButtonStates];
}
- (void)updateButtonStates {
    for (UIButton *button in self.filterButtons) {
        BOOL selected = button.tag == self.selectedFilter;
        button.titleLabel.font = [UIFont preferredFontForTextStyle:selected ? UIFontTextStyleHeadline : UIFontTextStyleCaption1];
        [button setTitleColor:selected ? UIColor.labelColor : UIColor.secondaryLabelColor forState:UIControlStateNormal];
        button.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
        button.transform = selected ? CGAffineTransformMakeScale(1.05,1.05) : CGAffineTransformIdentity;
    }
}
- (void)changeFilter:(UIButton *)sender {
    self.selectedFilter = sender.tag;
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self updateButtonStates];
        [self.filterContainer layoutIfNeeded];
    } completion:nil];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [sender titleForState:UIControlStateNormal]);
    [self filterData];
}
- (void)reloadAudit {
    NSMutableArray<NSDictionary *> *rows = [[FBTRuntimeBoolHookAuditSnapshot() mutableCopy] ?: [NSMutableArray array] mutableCopy];
    NSDictionary *probes = FBTMCNativeProbeStatus();
    NSArray *native = @[
       @{@"key": @"FBMobileConfigTigonFetcher::asyncFetch",
         @"registered": probes[@"fetcher_async_callback"] ?: @NO,
         @"enabled": probes[@"fetcher_session_enabled"] ?: @NO,
         @"reason": probes[@"fetcher_resolution"] ?: @"unknown",
         @"source": @"Tigon/RTTI"},
       @{@"key": @"TigonSimpleCallbacks",
         @"registered": probes[@"tigon_simple_callbacks"] ?: @NO,
         @"enabled": probes[@"tigon_session_enabled"] ?: @NO,
         @"reason": probes[@"tigon_resolution"] ?: @"unknown",
         @"source": @"Tigon callback"}
    ];
    for (NSDictionary *n in native) {
        BOOL installed = [n[@"registered"] boolValue];
        BOOL attempted = [n[@"enabled"] boolValue];
        [rows addObject:@{
            @"key": n[@"key"], @"class": @"C++ / Tigon", @"selector": n[@"key"],
            @"category": @"MobileConfig", @"source": n[@"source"],
            @"status": installed ? @"registered" : attempted ? @"pending" : @"not_requested",
            @"reason": n[@"reason"], @"registered": @(installed), @"invoked": @NO,
            @"saved": @NO, @"invocationCount": @0, @"activeForce": @NO,
            @"observedOriginal": NSNull.null, @"observedEffective": NSNull.null
        }];
    }
    self.allHooks = rows;
    [self filterData];
}
- (void)filterData {
    NSString *wanted = @[@"", @"invoked", @"registered", @"pending", @"rejected"][MIN(self.selectedFilter,4)];
    if (!wanted.length) self.visibleHooks = self.allHooks;
    else self.visibleHooks = [self.allHooks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, __unused NSDictionary *bindings) {
        return [item[@"status"] isEqualToString:wanted];
    }]];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return MAX(1,(NSInteger)self.visibleHooks.count); }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%lu hooks neste filtro · %lu registros totais", (unsigned long)self.visibleHooks.count,(unsigned long)self.allHooks.count];
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"FBTHookAuditCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FBTHookAuditCell"];
    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    if (!self.visibleHooks.count) {
        cfg.text = @"Nenhum hook neste estado";
        cfg.secondaryText = @"Arme a instrumentação e use o recurso nativo; atualize para observar invocações.";
    } else {
        NSDictionary *item = self.visibleHooks[ip.row];
        NSString *status = item[@"status"] ?: @"unknown";
        NSString *selector = item[@"selector"] ?: item[@"key"] ?: @"";
        NSString *name = [item[@"class"] length] ? [NSString stringWithFormat:@"%@[%@ %@]",
                [item[@"classMethod"] boolValue] ? @"+" : @"-", item[@"class"], selector] : item[@"key"];
        cfg.text = name;
        cfg.textProperties.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
        cfg.secondaryText = [NSString stringWithFormat:@"%@ · %@ · %@ chamadas\n%@\nPersistido: %@ · força ativa: %@",
            status.uppercaseString, item[@"source"] ?: @"runtime",
            item[@"invocationCount"] ?: @0,
            item[@"reason"] ?: @"",
            [item[@"saved"] boolValue] ? @"sim" : @"não",
            [item[@"activeForce"] boolValue] ? @"sim" : @"não"];
    }
    cfg.textProperties.numberOfLines = 0;
    cfg.secondaryTextProperties.numberOfLines = 0;
    cfg.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    cell.contentConfiguration = cfg;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (!self.visibleHooks.count) return;
    NSDictionary *item = self.visibleHooks[ip.row];
    NSString *text = [NSString stringWithFormat:
        @"%@\n\nOrigem: %@\nEstado: %@\nMotivo: %@\nRegistrado: %@\nInvocado: %@\nContagem: %@\nForça ativa: %@\nOriginal observado: %@\nEfetivo observado: %@\n\nSem invocação observada, não há prova de efeito.",
        item[@"key"] ?: @"", item[@"source"] ?: @"", item[@"status"] ?: @"",
        item[@"reason"] ?: @"", [item[@"registered"] boolValue] ? @"sim" : @"não",
        [item[@"invoked"] boolValue] ? @"sim" : @"não", item[@"invocationCount"] ?: @0,
        [item[@"activeForce"] boolValue] ? @"sim" : @"não",
        item[@"observedOriginal"] ?: NSNull.null, item[@"observedEffective"] ?: NSNull.null];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Auditoria do hook" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copiar detalhes" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = text;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Fechar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
