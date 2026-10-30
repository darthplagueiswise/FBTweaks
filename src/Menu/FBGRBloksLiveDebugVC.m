// FBTweaks live diagnostics UI. Safe in a sideloaded, injected host process.
#import <UIKit/UIKit.h>
#import "../Runtime/FBGRBloksTrace.h"
#import "FBGRMenuTheme.h"

@interface FBGRBloksLiveDebugVC : UIViewController <UISearchBarDelegate>
@end

@interface FBGRBloksLiveDebugVC ()
@property(nonatomic,strong) UISwitch *captureSwitch;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UISegmentedControl *scope;
@property(nonatomic,strong) UISearchBar *search;
@property(nonatomic,strong) UITextView *text;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *lastRendered;
@end

@implementation FBGRBloksLiveDebugVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Bloks Lab · Live Trace";
    self.view.backgroundColor = FBGRBg();
    UIScrollView *dummy = nil; (void)dummy;

    UILabel *captureLabel = [UILabel new];
    captureLabel.text = @"Captura observacional";
    captureLabel.textColor = FBGRText();
    captureLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

    _captureSwitch = [UISwitch new];
    _captureSwitch.on = FBGRBloksTraceIsEnabled();
    [_captureSwitch addTarget:self action:@selector(toggleCapture:) forControlEvents:UIControlEventValueChanged];

    UIStackView *toggleRow = [[UIStackView alloc] initWithArrangedSubviews:@[captureLabel,_captureSwitch]];
    toggleRow.axis = UILayoutConstraintAxisHorizontal;
    toggleRow.alignment = UIStackViewAlignmentCenter;
    toggleRow.distribution = UIStackViewDistributionEqualSpacing;
    toggleRow.translatesAutoresizingMaskIntoConstraints = NO;

    _status = [UILabel new];
    _status.numberOfLines = 0;
    _status.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _status.textColor = FBGRSub();
    _status.translatesAutoresizingMaskIntoConstraints = NO;

    _scope = [[UISegmentedControl alloc] initWithItems:@[@"Todos",@"VPN",@"Bloks",@"Erros"]];
    _scope.selectedSegmentIndex = 0;
    [_scope addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    _scope.translatesAutoresizingMaskIntoConstraints = NO;

    _search = [UISearchBar new];
    _search.placeholder = @"Filtrar eventos e campos";
    _search.delegate = self;
    _search.searchBarStyle = UISearchBarStyleMinimal;
    _search.translatesAutoresizingMaskIntoConstraints = NO;

    _text = [UITextView new];
    _text.editable = NO;
    _text.selectable = YES;
    _text.alwaysBounceVertical = YES;
    _text.backgroundColor = FBGRBg();
    _text.textColor = FBGRText();
    _text.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _text.textContainerInset = UIEdgeInsetsMake(8,6,8,6);
    _text.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *install = [self actionButton:@"Revalidar hooks" selector:@selector(reinstall)];
    UIButton *mark = [self actionButton:@"Marcar" selector:@selector(mark)];
    UIButton *clear = [self actionButton:@"Limpar" selector:@selector(clearTrace)];
    UIButton *export = [self actionButton:@"Exportar JSONL" selector:@selector(exportTrace)];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[install,mark,clear,export]];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.distribution = UIStackViewDistributionFillEqually;
    actions.spacing = 3;
    actions.translatesAutoresizingMaskIntoConstraints = NO;

    for (UIView *v in @[toggleRow,_status,_scope,_search,_text,actions])
        [self.view addSubview:v];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [toggleRow.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:14],
        [toggleRow.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-14],
        [toggleRow.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],

        [_status.topAnchor constraintEqualToAnchor:toggleRow.bottomAnchor constant:10],
        [_status.leadingAnchor constraintEqualToAnchor:toggleRow.leadingAnchor],
        [_status.trailingAnchor constraintEqualToAnchor:toggleRow.trailingAnchor],

        [_scope.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:10],
        [_scope.leadingAnchor constraintEqualToAnchor:toggleRow.leadingAnchor],
        [_scope.trailingAnchor constraintEqualToAnchor:toggleRow.trailingAnchor],

        [_search.topAnchor constraintEqualToAnchor:_scope.bottomAnchor constant:3],
        [_search.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_search.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],

        [_text.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:3],
        [_text.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_text.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],

        [actions.topAnchor constraintEqualToAnchor:_text.bottomAnchor constant:6],
        [actions.leadingAnchor constraintEqualToAnchor:toggleRow.leadingAnchor],
        [actions.trailingAnchor constraintEqualToAnchor:toggleRow.trailingAnchor],
        [actions.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [actions.heightAnchor constraintEqualToConstant:42]
    ]];
    // Install only after user enables capture or if persisted as enabled.
    if (FBGRBloksTraceIsEnabled()) FBGRBloksTraceInstall();
    [self refresh];
}
- (UIButton *)actionButton:(NSString *)title selector:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [b setTitle:title forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.8
        target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [self refresh];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}
- (void)toggleCapture:(UISwitch *)sw {
    FBGRBloksTraceSetEnabled(sw.isOn);
    [self refresh];
}
- (void)reinstall {
    FBGRBloksTraceInstall();
    [self refresh];
}
- (void)mark { FBGRBloksTraceMark(@"user.marker"); [self refresh]; }
- (void)clearTrace {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Apagar diagnóstico?"
        message:@"Apaga o registro atual; não altera o aplicativo nem os overrides."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar"
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Apagar"
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
            FBGRBloksTraceClear(); self.lastRendered=nil; [self refresh];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)exportTrace {
    NSURL *url = FBGRBloksTraceFileURL();
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sem eventos"
            message:@"Ative a captura e abra o Bloks Lab antes de exportar."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];
    if (share.popoverPresentationController)
        share.popoverPresentationController.sourceView = self.view;
    [self presentViewController:share animated:YES completion:nil];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self refresh];
}
- (void)refresh {
    self.status.text = [NSString stringWithFormat:@"%@\nCaptura: %@ · somente BOOLs e timestamps",
        FBGRBloksTraceStatus(), FBGRBloksTraceIsEnabled()?@"ligada":@"desligada"];
    NSString *raw = FBGRBloksTraceSnapshot();
    NSArray<NSString *> *lines = [raw componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:lines.count];
    NSString *query = self.search.text.lowercaseString;
    NSInteger selected = self.scope.selectedSegmentIndex;
    for (NSString *line in lines) {
        if (!line.length) continue;
        if (selected==1 && [line rangeOfString:@"VPN" options:NSCaseInsensitiveSearch].location==NSNotFound) continue;
        if (selected==2 && [line rangeOfString:@"bloks" options:NSCaseInsensitiveSearch].location==NSNotFound) continue;
        if (selected==3 && [line rangeOfString:@"error" options:NSCaseInsensitiveSearch].location==NSNotFound) continue;
        if (query.length && [line.lowercaseString rangeOfString:query].location==NSNotFound) continue;
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *event = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        if (![event isKindOfClass:NSDictionary.class]) { [out addObject:line]; continue; }
        NSString *name = event[@"event"] ?: @"event";
        NSNumber *timestamp = event[@"time_unix_ms"];
        NSDate *date = timestamp ? [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue / 1000.0] : nil;
        NSDateFormatter *fmt = [NSDateFormatter new];
        fmt.dateFormat = @"HH:mm:ss.SSS";
        NSString *time = date ? [fmt stringFromDate:date] : @"--:--:--";
        NSMutableArray *fields = [NSMutableArray array];
        for (NSString *key in [[event allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            if ([key isEqualToString:@"event"] || [key isEqualToString:@"time_unix_ms"]) continue;
            [fields addObject:[NSString stringWithFormat:@"%@=%@",key,event[key]]];
        }
        [out addObject:[NSString stringWithFormat:@"%@  %@\n  %@",
            time,name,[fields componentsJoinedByString:@"  "]]];
    }
    NSString *rendered = out.count ? [out componentsJoinedByString:@"\n\n"] :
        @"Sem eventos correspondentes.\nAtive a captura, feche este painel e abra o Bloks Lab.";
    if ([rendered isEqualToString:self.lastRendered]) return;
    self.lastRendered=rendered;
    CGFloat oldOffset = self.text.contentOffset.y;
    BOOL atBottom = oldOffset + self.text.bounds.size.height >= self.text.contentSize.height - 75;
    self.text.text=rendered;
    if (atBottom && rendered.length) {
        [self.text scrollRangeToVisible:NSMakeRange(rendered.length-1,1)];
    } else {
        [self.text setContentOffset:CGPointMake(0,MAX(0,oldOffset)) animated:NO];
    }
}
@end
