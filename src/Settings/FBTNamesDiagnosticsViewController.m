#import "FBTNamesDiagnosticsViewController.h"
#import "../FBTDefaults.h"
#import "../FBTUtils.h"
#import "FBTLocalConfigViewController.h"
#import "../Runtime/FBTNamesResponseSummary.h"
#import "../Runtime/FBTMobileConfigFetchDiagnostics.h"
#import "../Runtime/FBTMobileConfigResponseCapture.h"
#import "../Runtime/FBTMobileConfigDebugUIHooks.h"

@interface FBTNamesDiagnosticsViewController ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSDictionary *report;
@property (nonatomic, copy) NSArray<NSDictionary *> *history;
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
    NSString *process = self.report[@"process_session_id"];
    NSMutableArray *requests = [NSMutableArray array];
    NSDictionary *lastDownload = nil;
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        if (![event[@"process_session_id"] isEqual:process]) continue;
        if (!lastDownload && [event[@"event"] isEqual:@"name_download_completed"]) lastDownload = event;
        if ([event[@"event"] isEqual:@"native_mc_fetch_started"] &&
            [event[@"capture_reason"] isEqual:@"mobileconfig_qe_info"]) [requests addObject:event];
    }
    NSMutableArray *history = [NSMutableArray array];
    for (NSDictionary *request in requests) {
        NSDictionary *diagnostic = nil, *completion = nil;
        for (NSDictionary *event in events.reverseObjectEnumerator) {
            if (![event[@"process_session_id"] isEqual:process] || ![event[@"request_id"] isEqual:request[@"request_id"]]) continue;
            if ([event[@"event"] isEqual:@"native_mc_fetch_completed"] && !completion) completion = event;
            if ([event[@"event"] isEqual:@"names_transport_diagnostic"] &&
                (!diagnostic || ([diagnostic[@"http_status"] integerValue] == 0 && [event[@"http_status"] integerValue] > 0))) diagnostic = event;
        }
        [history addObject:@{@"request": request, @"diagnostic": diagnostic ?: @{}, @"completion": completion ?: @{}}];
        if (history.count == 8) break;
    }
    self.history = history;
    NSDictionary *entry = history.firstObject ?: @{};
    NSDictionary *request = entry[@"request"], *diagnostic = entry[@"diagnostic"], *completion = entry[@"completion"];
    NSDictionary *advice = FBTNamesDiagnosticAdvice(diagnostic ?: @{});
    NSDictionary *assessment = FBTNamesAssessRequest(request ?: @{}, diagnostic ?: @{}, completion ?: @{});
    NSString *interpretation = [NSString stringWithFormat:@"Perfil: %@\n%@\n\nTransporte: %@ · nomes: %@\n%@\n\n%@\n\n%@\n\n%@", assessment[@"request_profile"], assessment[@"request_options_explanation"], assessment[@"transport_state"], assessment[@"names_payload_state"], assessment[@"native_callback_explanation"], assessment[@"authentication_explanation"], assessment[@"whitehat_explanation"], assessment[@"next_step"]];
    BOOL enabled = [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
    BOOL installed = [transport[@"native_mc_fetcher_installed"] boolValue] && [transport[@"simple_callback_hooks_installed"] boolValue];
    NSString *readiness = !enabled ? @"Captura pausada" : installed ? @"Captura nativa pronta" : @"Captura incompleta — verifique os hooks";
    NSString *status = [NSString stringWithFormat:@"%@\nPedidos nativos: %@ · conclusões: %@\nCorrelações de transporte: %@\n%@%@",
        readiness, transport[@"native_mc_requests"] ?: @0, transport[@"native_mc_responses"] ?: @0,
        transport[@"native_tigon_correlations"] ?: @0,
        [transport[@"native_mc_fetcher_installed"] boolValue] ? @"" : (transport[@"native_mc_fetcher_failure"] ?: @"Fetcher não instalado. "),
        [transport[@"simple_callback_hooks_installed"] boolValue] ? @"" : (transport[@"simple_callback_failure"] ?: @"Callbacks não instalados.")];
    NSString *requestText = request ? [NSString stringWithFormat:@"Pedido %@ · %@ · %@\n%@",
        request[@"request_id"], request[@"request_method"] ?: @"?", request[@"time_utc"] ?: @"", request[@"request_parameter_summary"] ?: @""] : @"Aguardando tentativa pelo menu nativo.";
    NSString *result = diagnostic.count ? [NSString stringWithFormat:@"HTTP %@ · %@\n%@ bytes recebidos\nCódigo %@ · subcódigo %@ · %@\n%@",
        [diagnostic[@"http_status"] integerValue] ? diagnostic[@"http_status"] : @"não observado", diagnostic[@"body_status"] ?: @"sem estado",
        diagnostic[@"response_bytes"] ?: @0, diagnostic[@"server_error_code"] ?: @"não fornecido",
        diagnostic[@"server_error_subcode"] ?: @"não fornecido", diagnostic[@"server_error_type"] ?: @"tipo não fornecido",
        diagnostic[@"server_error_message"] ?: @"Nenhuma mensagem remota disponível."] :
        (completion.count ? [NSString stringWithFormat:@"Conclusão nativa: %@\n%@\nCorpo HTTP não capturado.",
            [completion[@"native_transport_success"] boolValue] ? @"sucesso" : @"falha", completion[@"message"] ?: @""] : @"Aguardando conclusão do pedido.");
    if ([diagnostic[@"id_to_names_valid"] boolValue]) result = [result stringByAppendingFormat:@"\nid_to_names: %@ registros.", diagnostic[@"id_to_names_count"] ?: @0];
    NSDictionary *app = self.report[@"session_settings"][@"host_app"] ?: @{};
    NSString *localState = [NSString stringWithFormat:@"Aplicativo: %@ · %@ (%@)\nEstados no arquivo local, não prova de autorização remota:\nLegacy refresh: %@\nBuiltin query hash: %@\nÚltima conclusão do download de nomes: %@",
        app[@"bundle_id"] ?: @"não registrado", app[@"version"] ?: @"?", app[@"build"] ?: @"?",
        lastDownload[@"legacy_refresh_override_file_state"] ?: @"não observado", lastDownload[@"builtin_query_hash_override_file_state"] ?: @"não observado",
        lastDownload ? ([lastDownload[@"download_success"] boolValue] ? @"sucesso nativo" : @"falha nativa") : @"não observada"];
    NSMutableArray *historyText = [NSMutableArray array];
    for (NSDictionary *item in history) {
        NSDictionary *r = item[@"request"], *d = item[@"diagnostic"];
        [historyText addObject:[NSString stringWithFormat:@"Pedido %@ · HTTP %@ · %@\n%@", r[@"request_id"],
            [d[@"http_status"] integerValue] ? d[@"http_status"] : @"?", r[@"time_utc"] ?: @"", d[@"server_error_message"] ?: d[@"body_status"] ?: @"aguardando"]];
    }
    if (!historyText.count) [historyText addObject:@"Nenhum pedido QE-info registrado nesta sessão."];
    self.rows = @[@[@"Iniciar nova captura", @"Pausar captura", @"Copiar relatório JSON", @"Abrir mapa local"],
        @[status, [NSString stringWithFormat:@"%@\n\n%@\n\n%@", advice[@"title"], advice[@"explanation"], advice[@"next_step"]]],
        @[requestText, result, localState, interpretation], historyText,
        @[@"1. Inicie a captura aqui.\n2. Execute Internal Settings → MobileConfig → Advanced Settings → Force name download uma vez.\n3. Retorne e use Compartilhar.\n\nA captura continua com esta tela fechada e funciona sem Frida ou computador. O mapa local funciona sem o serviço QE-info e não anuncia sucesso remoto."]];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.rows.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Controles", @"Diagnóstico", @"Evidências", @"Histórico da sessão — toque para detalhes", @"Como usar"][section];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NamesDiagnostic"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"NamesDiagnostic"];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.text = self.rows[path.section][path.row];
    cell.textLabel.textColor = path.section == 0 ? UIColor.systemBlueColor : UIColor.labelColor;
    cell.selectionStyle = (path.section == 0 || (path.section == 3 && self.history.count)) ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 3 && path.row < self.history.count) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:self.history[path.row] options:NSJSONWritingPrettyPrinted error:nil];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        UIAlertController *detail = [UIAlertController alertControllerWithTitle:@"Detalhes do pedido" message:text preferredStyle:UIAlertControllerStyleAlert];
        [detail addAction:[UIAlertAction actionWithTitle:@"Copiar" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = text; }]];
        [detail addAction:[UIAlertAction actionWithTitle:@"Fechar" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:detail animated:YES completion:nil]; return;
    }
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
    } else if (path.row == 2) [UIPasteboard generalPasteboard].string = FBTMobileConfigFetchDiagnosticsJSON();
    else [self.navigationController pushViewController:[[FBTLocalConfigViewController alloc] initWithSearchQuery:@""] animated:YES];
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

@interface FBTNamesDiagnosticsNavigationController : UINavigationController
- (void)closeDiagnostics;
@end
@implementation FBTNamesDiagnosticsNavigationController
- (void)closeDiagnostics { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

void FBTPresentNamesDiagnostics(UIViewController *presenter) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ FBTPresentNamesDiagnostics(presenter); }); return; }
    if (!presenter) presenter = [FBTUtils topMostController];
    if (!presenter) return;
    FBTNamesDiagnosticsViewController *panel = [[FBTNamesDiagnosticsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    if (presenter.navigationController) { [presenter.navigationController pushViewController:panel animated:YES]; return; }
    FBTNamesDiagnosticsNavigationController *nav = [[FBTNamesDiagnosticsNavigationController alloc] initWithRootViewController:panel];
    panel.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:nav action:@selector(closeDiagnostics)];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [presenter presentViewController:nav animated:YES completion:nil];
}

