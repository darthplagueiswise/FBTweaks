#import "FBGRLogViewController.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRLog.h"

@interface FBGRLogViewController ()
@property(nonatomic, strong) UITextView *tv;
@end
@implementation FBGRLogViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Log";
    self.view.backgroundColor = FBGRBg();
    _tv = [[UITextView alloc] initWithFrame:CGRectZero];
    _tv.translatesAutoresizingMaskIntoConstraints = NO;
    _tv.editable = NO; _tv.alwaysBounceVertical = YES;
    _tv.backgroundColor = FBGRBg(); _tv.textColor = FBGRText();
    _tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _tv.textContainerInset = UIEdgeInsetsMake(10,8,10,8);
    [self.view addSubview:_tv];
    [NSLayoutConstraint activateConstraints:@[
        [_tv.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    UIBarButtonItem *r = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
        target:self action:@selector(refresh)];
    UIBarButtonItem *c = [[UIBarButtonItem alloc] initWithTitle:@"Limpar"
        style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
    UIBarButtonItem *cp = [[UIBarButtonItem alloc] initWithTitle:@"Copiar"
        style:UIBarButtonItemStylePlain target:self action:@selector(copy2)];
    self.navigationItem.rightBarButtonItems = @[r, cp];
    self.navigationItem.leftBarButtonItem = c;
    [self refresh];
}
- (void)refresh {
    _tv.text = FBGRLogSnapshot();
    if (_tv.text.length > 1) [_tv scrollRangeToVisible:NSMakeRange(_tv.text.length-1, 1)];
}
- (void)clear  { FBGRLogClear(); [self refresh]; }
- (void)copy2  { [UIPasteboard generalPasteboard].string = _tv.text ?: @""; }
@end
