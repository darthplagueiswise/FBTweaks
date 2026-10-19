#import "FBTNativeTraceViewController.h"
#import "../Runtime/FBTNativeTrace.h"
#import "../FBTDefaults.h"
@interface FBTNativeTraceViewController ()
@property(nonatomic,copy) NSArray<NSDictionary*> *items;
@property(nonatomic,strong) UISwitch *captureSwitch;
@end
@implementation FBTNativeTraceViewController
- (void)viewDidLoad{
 [super viewDidLoad];
 self.title=@"Live Trace";
 [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TraceRow"];
 self.captureSwitch=[UISwitch new];
 self.captureSwitch.on=[FBTDefaults boolForKey:FBTKeyNativeTraceEnabled];
 [self.captureSwitch addTarget:self action:@selector(toggleCapture:) forControlEvents:UIControlEventValueChanged];
 UILabel *label=[UILabel new];
 label.text=@"Capturar ";label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
 UIStackView *controls=[[UIStackView alloc]initWithArrangedSubviews:@[label,self.captureSwitch]];
 controls.axis=UILayoutConstraintAxisHorizontal;controls.spacing=4;
 self.navigationItem.titleView=controls;
 self.navigationItem.rightBarButtonItems=@[
  [[UIBarButtonItem alloc]initWithTitle:@"Exportar" style:UIBarButtonItemStylePlain target:self action:@selector(exportTrace)],
  [[UIBarButtonItem alloc]initWithTitle:@"Limpar" style:UIBarButtonItemStylePlain target:self action:@selector(clearTrace)],
  [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshTrace)]
 ];
 [self refreshTrace];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self refreshTrace];}
- (void)toggleCapture:(UISwitch*)sender{
 [FBTDefaults setBool:sender.isOn forKey:FBTKeyNativeTraceEnabled];
 FBTNativeTraceReloadPrefs();[self refreshTrace];
}
- (void)refreshTrace{
 NSDictionary *snap=FBTNativeTraceSnapshot();
 self.items=snap[@"events"]?:@[];
 self.tableView.backgroundView=self.items.count?nil:[self emptyMessage];
 [self.tableView reloadData];
}
- (UIView*)emptyMessage{
 UILabel*label=[UILabel new];
 label.text=@"Nenhum evento registrado. Ative a captura e reproduza o getter ou o fetch QE-info.";
 label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;
 label.textColor=[UIColor secondaryLabelColor];return label;
}
- (void)clearTrace{FBTNativeTraceClear();[self refreshTrace];}
- (void)exportTrace{
 NSData *data=[NSJSONSerialization dataWithJSONObject:FBTNativeTraceSnapshot() options:NSJSONWritingPrettyPrinted error:nil];
 if(!data.length)return;
 NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"fbt_native_live_trace.json"];
 if(![data writeToFile:path atomically:YES])return;
 UIActivityViewController *activity=[[UIActivityViewController alloc]initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
 activity.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.firstObject;
 [self presentViewController:activity animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section{return self.items.count;}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath{
 UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"TraceRow" forIndexPath:indexPath];
 NSDictionary *record=self.items[indexPath.row];
 UIListContentConfiguration *cfg=[cell defaultContentConfiguration];
 cfg.text=[NSString stringWithFormat:@"%@ · %@",record[@"kind"],record[@"name"]];
 id original=record[@"original"],effective=record[@"effective"];
 NSString *originalValue=original==[NSNull null]?@"não observado":[original boolValue]?@"ON":@"OFF";
 NSString *effectiveValue=effective==[NSNull null]?@"não observado":[effective boolValue]?@"ON":@"OFF";
 cfg.secondaryText=[record[@"kind"] isEqualToString:@"BOOL"]?
  [NSString stringWithFormat:@"original=%@ · efetivo=%@ · #%@",originalValue,effectiveValue,record[@"sequence"]]:
  [NSString stringWithFormat:@"%@ · #%@",record[@"detail"],record[@"sequence"]];
 cfg.secondaryTextProperties.numberOfLines=3;cell.contentConfiguration=cfg;return cell;
}
@end
