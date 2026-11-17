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
 self.captureSwitch.on=FBTNativeTraceIsEnabled();
 [self.captureSwitch addTarget:self action:@selector(toggleCapture:) forControlEvents:UIControlEventValueChanged];
 self.captureSwitch.accessibilityLabel=@"Capturar eventos do Live Trace";
 UILabel *label=[UILabel new];
 label.text=@"Capturar eventos";
 label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
 label.adjustsFontForContentSizeCategory=YES;
 label.numberOfLines=0;
 label.textColor=UIColor.labelColor;
 UIStackView *controls=[[UIStackView alloc]initWithArrangedSubviews:@[label,self.captureSwitch]];
 controls.axis=UILayoutConstraintAxisHorizontal;
 controls.alignment=UIStackViewAlignmentCenter;
 controls.spacing=16;
 controls.translatesAutoresizingMaskIntoConstraints=NO;
 UIView *header=[[UIView alloc]initWithFrame:CGRectZero];
 [header addSubview:controls];
 [NSLayoutConstraint activateConstraints:@[
  [controls.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],
  [controls.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
  [controls.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
  [controls.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12]
 ]];
 self.tableView.tableHeaderView=header;
 __weak typeof(self) weakSelf=self;
 UIAction *exportAction=[UIAction actionWithTitle:@"Exportar" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(__unused UIAction *action){[weakSelf exportTrace];}];
 UIAction *clearAction=[UIAction actionWithTitle:@"Limpar" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused UIAction *action){[weakSelf clearTrace];}];
 clearAction.attributes=UIMenuElementAttributesDestructive;
 UIBarButtonItem *actions=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:nil action:NULL];
 actions.menu=[UIMenu menuWithChildren:@[exportAction,clearAction]];
 actions.accessibilityLabel=@"Ações do Live Trace";
 self.navigationItem.rightBarButtonItems=@[
  actions,
  [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshTrace)]
 ];
 [self refreshTrace];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self refreshTrace];}
- (void)toggleCapture:(UISwitch*)sender{
 // An explicit OFF also stops a buffer armed by a native capture action.
 FBTNativeTraceSetSessionCaptureEnabled(NO);
 [FBTDefaults setBool:sender.isOn forKey:FBTKeyNativeTraceEnabled];
 FBTNativeTraceReloadPrefs();[self refreshTrace];
}
- (void)refreshTrace{
 NSDictionary *snap=FBTNativeTraceSnapshot();
 self.captureSwitch.on=[snap[@"enabled"] boolValue];
 self.items=snap[@"events"]?:@[];
 self.tableView.backgroundView=self.items.count?nil:[self emptyMessage:snap];
 [self.tableView reloadData];
}
- (UIView*)emptyMessage:(NSDictionary*)snapshot{
 UILabel*label=[UILabel new];
 if(![snapshot[@"enabled"] boolValue])
  label.text=@"Live Trace desligado. Inicie uma captura ou ative Capturar antes de reproduzir a ação.";
 else if([snapshot[@"observation_state"] isEqual:@"dropped_on_contention"])
  label.text=@"Coletor ativo; eventos descartados por contenção. Reproduza a ação e atualize.";
 else if([snapshot[@"network_source_state"] isEqual:@"hook_unavailable"])
  label.text=@"Coletor ativo; hook nativo indisponível. Confira os probes. Nenhum evento foi observado.";
 else if([snapshot[@"network_source_state"] isEqual:@"unknown"])
  label.text=@"Coletor ativo; estado do hook nativo desconhecido. Confira os probes. Nenhum evento foi observado.";
 else if([snapshot[@"network_source_state"] isEqual:@"armed"])
  label.text=@"Coletor ativo e probe nativo armado. Nenhum evento observado; reproduza o fetch e atualize.";
 else
  label.text=@"Coletor ativo; probes de rede desarmados. Observe um getter BOOL ou arme um probe nativo e reproduza a ação.";
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
