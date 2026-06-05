#import "FBGRLogViewController.h"
#import "FBGRMenuTheme.h"
#import "../Runtime/FBGRLog.h"
@implementation FBGRLogViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Logs"; FBGRApplyGlassController(self);
    UITextView *tv=[[UITextView alloc] initWithFrame:self.view.bounds]; tv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; tv.editable=NO; tv.backgroundColor=UIColor.clearColor; tv.textColor=FBGRTextColor(); tv.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; tv.text=FBGRLogSnapshot(); [self.view addSubview:tv];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Limpar" style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
}
- (void)clear { FBGRLogClear(); [self.navigationController popViewControllerAnimated:YES]; }
@end
