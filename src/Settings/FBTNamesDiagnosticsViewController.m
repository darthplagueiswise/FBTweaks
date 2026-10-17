#import "FBTNamesDiagnosticsViewController.h"
#import "../FBTDefaults.h"
#import "../Runtime/FBTMobileConfigFetchDiagnostics.h"
#import "../Runtime/FBTMobileConfigResponseCapture.h"
#import "../Runtime/FBTMobileConfigDebugUIHooks.h"

@interface FBTNamesDiagnosticsViewController ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSDictionary *report;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *rows;
@end

@implementation FBTNamesDiagnosticsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Diagnóstico de nomes";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareReport)];
    [self refreshReport];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf refreshReport];
    }];
    [self refreshReport];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.timer invalidate]; self.timer = nil;
}
- (void)dealloc { [_timer invalidate]; }
- (void)refreshReport {
    self.report = FBTMobileConfigFetchDiagnosticsSnapshot();
    NSDictionary *transport = self.report[@"transport"] ?: @{};
    NSArray *events = self.report[@"events"] ?: @[];
    NSDictionary *request = nil, *diagnostic = nil, *completion = nil;
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        if (!request && [event[@"event"] isEqual:@"native_mc_fetch_started"] &&
            [event[@"capture_reason"] isEqual:@"mobileconfig_qe_info"]) request = event;
    }
    // Show a single exact request, never the last body from an unrelated sync.
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        if (!request || ![event[@"request_id"] isEqual:request[@"request_id"]] ||
            ![event[@"process_session_id"] isEqual:request[@"process_session_id"]]) continue;
        if (!diagnostic && [event[@"event"] isEqual:@"names_transport_diagnostic"]) diagnostic = event;
        if (!completion && [event[@"event"] isEqual:@"native_mc_fetch_completed"]) completion = event;
    }
    BOOL enabled = [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
    NSString *hooks = [NSString stringWithFormat:@"Captura %@\nFetcher nativo: %@\nCallbacks de transporte: %@%@",
        enabled ? @"ligada" : @"pausada",
        [transport[@"native_mc_fetcher_installed"] boolValue] ? @"instalado" : (transport[@"native_mc_fetcher_failure"] ?: @"aguardando"),
        [transport[@"simple_callback_hooks_installed"] boolValue] ? @"instalados" : @"indisponíveis: ",
        [transport[@"simple_callback_hooks_installed"] boolValue] ? @"" : (transport[@"simple_callback_failure"] ?: @"não iniciados")];
    NSString *requestText = request ? [NSString stringWithFormat:@"Pedido %@ · %@\n%@",
        request[@"request_id"], request[@"request_method"] ?: @"?", request[@"request_parameter_summary"] ?: @""] : @"Aguardando tentativa de Force name download.";
    NSString *result = diagnostic ? [NSString stringWithFormat:@"HTTP %@ · %@\n%@ bytes recebidos\nCódigo remoto: %@ · subcódigo: %@\nTipo: %@\n%@",
        diagnostic[@"http_status"] ?: @"não observado", diagnostic[@"body_status"] ?: @"sem estado",
        diagnostic[@"response_bytes"] ?: @0, diagnostic[@"server_error_code"] ?: @"não fornecido",
        diagnostic[@"server_error_subcode"] ?: @"não fornecido", diagnostic[@"server_error_type"] ?: @"não fornecido",
        diagnostic[@"server_error_message"] ?: @"Nenhuma mensagem remota disponível nessa superfície."] :
        (completion ? [NSString stringWithFormat:@"Conclusão nativa: %@\n%@\nCorpo HTTP não capturado; confira os hooks acima.",
            [completion[@"native_transport_success"] boolValue] ? @"sucesso" : @"falha", completion[@"message"] ?: @""] : @"Aguardando conclusão do pedido.");
    if ([diagnostic[@"id_to_names_valid"] boolValue]) result = [result stringByAppendingFormat:@"\nid_to_names válido: %@ registros. A gravação do arquivo é uma etapa separada.", diagnostic[@"id_to_names_count"] ?: @0];
    self.rows = @[@[@"Iniciar nova captura", @"Pausar captura", @"Copiar relatório JSON"],
                  @[hooks, requestText, result],
                  @[@"1. Inicie a captura aqui.\n2. Volte ao Internal Settings → MobileConfig → Advanced Settings → Force name download e tente uma vez.\n3. Retorne a esta tela e use Compartilhar para enviar o JSON pelo iPhone.\n\nA captura continua enquanto esta tela está fechada. Não precisa de Frida nem de computador."]];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.rows.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Controles", @"Pedido e resultado", @"Como usar"][section];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NamesDiagnostic"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"NamesDiagnostic"];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.text = self.rows[path.section][path.row];
    cell.textLabel.textColor = path.section == 0 ? UIColor.systemBlueColor : UIColor.labelColor;
    cell.selectionStyle = path.section == 0 ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section != 0) return;
    if (path.row == 0) {
        [FBTDefaults setBool:YES forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
        FBTMobileConfigResponseCaptureInstall();
        FBTInstallMobileConfigDebugUIBootstrap();
        FBTMobileConfigFetchDiagnosticsReset();
        FBTMobileConfigResponseCaptureArm(@"force_name_download");
    } else if (path.row == 1) {
        FBTMobileConfigFetchDiagnosticsRecord(@"capture_paused", @{});
        [FBTDefaults setBool:NO forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
        FBTMobileConfigResponseCaptureDisarm();
    } else [UIPasteboard generalPasteboard].string = FBTMobileConfigFetchDiagnosticsJSON();
    [self refreshReport];
}
- (void)shareReport {
    NSString *json = FBTMobileConfigFetchDiagnosticsJSON();
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"FBTNames-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self showExportFailure]; return;
    }
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"fbt_names_diagnostic.json"]];
    if (![json writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
        [self showExportFailure]; return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    activity.completionWithItemsHandler = ^(__unused UIActivityType type, __unused BOOL completed, __unused NSArray *items, __unused NSError *activityError) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
    };
    [self presentViewController:activity animated:YES completion:nil];
}
- (void)showExportFailure {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Não foi possível exportar" message:@"Use Copiar relatório JSON ou tente novamente." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
