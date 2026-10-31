#import "FBTNamesDiagnosticsViewController.h"
#import "../FBTDefaults.h"
#import "../FBTUtils.h"
#import "FBTLocalConfigViewController.h"
#import "../Runtime/FBTNamesResponseSummary.h"
#import "../Runtime/FBTMobileConfigFetchDiagnostics.h"
#import "../Runtime/FBTMobileConfigResponseCapture.h"
#import "../Runtime/FBTMobileConfigDebugUIHooks.h"
#import "../Runtime/FBTMobileConfigRuntime.h"
#import "../Runtime/FBTEmployeeDiagnostics.h"
#import "../Runtime/FBTNativeTrace.h"
#import "../Runtime/FBTMCNativeSessionProbes.h"
#import "FBTNetworkInspectorViewController.h"
#import "FBTNativeTraceViewController.h"
extern void FBTInitEmployeeGroup(void);

@interface FBTNamesDiagnosticsViewController ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSDictionary *report;
@property (nonatomic, copy) NSArray<NSDictionary *> *history;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *rows;
@property (nonatomic, assign) NSInteger selectedProfile;
@end

@implementation FBTNamesDiagnosticsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Centro de Diagnósticos";
    self.selectedProfile = 0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
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
        [historyText addObject:[NSString stringWithFormat:@"Pedido %@ · %@ · HTTP %@ · %@\n%@", r[@"request_id"], r[@"experiment_profile"] ?: @"native",
            [d[@"http_status"] integerValue] ? d[@"http_status"] : @"?", r[@"time_utc"] ?: @"", d[@"server_error_message"] ?: d[@"body_status"] ?: @"aguardando"]];
    }
    if (!historyText.count) [historyText addObject:@"Nenhum pedido QE-info registrado nesta sessão."];
    NSDictionary *identity = self.report[@"employee_identity"] ?: @{};
    NSString *identityText = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:identity options:NSJSONWritingPrettyPrinted error:nil] encoding:NSUTF8StringEncoding] ?: @"";
    NSString *authText = [NSString stringWithFormat:@"Authorization: %@ · esquema: %@ · credencial: %@\nEtapa: %@\nExperimento: %@ · %@\nA presença de OAuth não confirma elegibilidade nem validade do token.",
        completion[@"authorization_state"] ?: @"não observado", completion[@"authorization_scheme"] ?: @"não observado",
        completion[@"authorization_credential_present"] ?: @"não observada", completion[@"authorization_observation_stage"] ?: @"não observada",
        request[@"experiment_profile"] ?: @"native", request[@"experiment_state"] ?: @"original"];
    NSDictionary *pending = FBTMobileConfigEmployeeExperimentStatus();
    NSDictionary *fullState = FBTMobileConfigFullQEInfoRequestStatus();
    NSInteger secondsRemaining = [pending[@"expires_in_seconds"] integerValue];
    NSString *armedText = [pending[@"armed"] boolValue] ?
        [NSString stringWithFormat:@"%@ · %ld s restantes", pending[@"profile"] ?: @"QE", (long)secondsRemaining] :
        @"Nenhum teste armado";
    NSString *lastEmployee = request.count ? [NSString stringWithFormat:
        @"Último pedido: %@ · is_employee acrescentado: %@",
        request[@"experiment_profile"] ?: @"native",
        [request[@"employee_field_added"] boolValue] ? @"SIM" : @"NÃO"] : @"Nenhum pedido QE-info desta sessão";
    BOOL capture = [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
    BOOL fetcherProbe = FBTMCNativeProbeIsEnabled(FBTMCNativeProbeFetcherKey);
    BOOL tigonProbe = FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey);
    self.rows = @[
        @[status, armedText, lastEmployee],
        @[[NSString stringWithFormat:@"Captura de diagnósticos: %@", capture ? @"ON" : @"OFF"],
          [NSString stringWithFormat:@"Probe asyncFetch: %@", fetcherProbe ? @"ON" : @"OFF"],
          [NSString stringWithFormat:@"Probe Tigon: %@", tigonProbe ? @"ON" : @"OFF"]],
        @[@"Perfil A (nativo) ou B (is_employee=true)",
          [pending[@"armed"] boolValue] ? @"Rearmar experimento" : @"Armar próximo QE-info",
          @"Cancelar experimento",
          [fullState[@"armed"] boolValue] ?
              [NSString stringWithFormat:@"QE completo armado · %@ s", fullState[@"expires_in_seconds"]] :
              @"Armar opções QE completas"],
        @[requestText, result, interpretation, localState, authText, identityText],
        @[@"Network Inspector", @"Catálogo MobileConfig", @"Native Live Trace",
          @"Copiar JSON do diagnóstico", @"Compartilhar relatório"]
    ];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.rows.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Visão geral", @"Captura e transporte", @"Experimento QE-info", @"Evidências", @"Ferramentas"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) return @"Apenas o próximo POST mobileconfig_qe_info consome o teste (120 s). Armar não dispara uma requisição. Se não aparecer 'is_employee acrescentado: SIM' no pedido, examine a instalação do probe.";
    if (section == 1) return @"Os probes dependem da captura. Um switch ligado não comprova resposta HTTP nem autorização Employee.";
    return nil;
}
- (UIButton *)fbtActionButton:(NSString *)title prominent:(BOOL)prominent identifier:(NSString *)identifier action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg;
    if (@available(iOS 26.0, *)) {
        cfg = prominent ? [UIButtonConfiguration prominentGlassButtonConfiguration] : [UIButtonConfiguration glassButtonConfiguration];
    } else {
        cfg = prominent ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration tintedButtonConfiguration];
    }
    cfg.title = title;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    button.configuration = cfg;
    button.frame = CGRectMake(0, 0, 132, 42);
    button.accessibilityIdentifier = identifier;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DiagnosticHub"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DiagnosticHub"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIListContentConfiguration *cfg = [cell defaultContentConfiguration];
    cfg.text = self.rows[path.section][path.row];
    cfg.textProperties.numberOfLines = 0;
    cfg.secondaryTextProperties.numberOfLines = 0;
    if (path.section == 1) {
        UISwitch *sw = [UISwitch new];
        sw.tag = 100 + path.row;
        sw.accessibilityIdentifier = @[@"fbt.diagnostics.capture", @"fbt.diagnostics.fetcher", @"fbt.diagnostics.tigon"][path.row];
        sw.on = path.row == 0 ? [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled] :
            FBTMCNativeProbeIsEnabled(path.row == 1 ? FBTMCNativeProbeFetcherKey : FBTMCNativeProbeTigonKey);
        [sw addTarget:self action:@selector(diagnosticsSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (path.section == 2) {
        if (path.row == 0) {
            UISegmentedControl *profiles = [[UISegmentedControl alloc] initWithItems:@[@"A · Nativo", @"B · Employee"]];
            profiles.selectedSegmentIndex = self.selectedProfile;
            profiles.accessibilityIdentifier = @"fbt.diagnostics.profile";
            profiles.frame = CGRectMake(0, 0, 187, 38);
            [profiles addTarget:self action:@selector(profileChanged:) forControlEvents:UIControlEventValueChanged];
            cfg.text = @"Perfil";
            cell.accessoryView = profiles;
        } else if (path.row == 1) {
            cell.accessoryView = [self fbtActionButton:@"Armar teste" prominent:YES
                identifier:@"fbt.diagnostics.arm" action:@selector(armExperiment:)];
        } else if (path.row == 2) {
            cell.accessoryView = [self fbtActionButton:@"Cancelar" prominent:NO
                identifier:@"fbt.diagnostics.cancel" action:@selector(cancelExperiment:)];
        } else if (path.row == 3) {
            cell.accessoryView = [self fbtActionButton:@"Armar QE" prominent:NO
                identifier:@"fbt.diagnostics.qe-full" action:@selector(armFullQE:)];
        }
    } else if (path.section == 4) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.contentConfiguration = cfg;
    return cell;
}
- (void)showDiagnosticInfo:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)profileChanged:(UISegmentedControl *)control {
    self.selectedProfile = control.selectedSegmentIndex;
    [self refreshReport];
}
- (void)diagnosticsSwitchChanged:(UISwitch *)control {
    if (control.tag == 100) {
        [FBTDefaults setBool:control.isOn forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
        if (control.isOn) {
            FBTNativeTraceSetSessionCaptureEnabled(YES);
            FBTMobileConfigResponseCaptureInstall();
            FBTInstallMobileConfigDebugUIBootstrap();
            FBTMobileConfigFetchDiagnosticsRecord(@"capture_started", @{@"source": @"diagnostics_hub"});
        } else {
            FBTMCNativeProbeDisableAll();
            FBTMobileConfigCancelEmployeeExperiment();
            FBTMobileConfigCancelFullQEInfoRequest();
            FBTNativeTraceSetSessionCaptureEnabled(NO);
            FBTMobileConfigFetchDiagnosticsRecord(@"capture_paused", @{@"source": @"diagnostics_hub"});
        }
    } else {
        NSString *key = control.tag == 101 ? FBTMCNativeProbeFetcherKey : FBTMCNativeProbeTigonKey;
        if (control.isOn && ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
            [FBTDefaults setBool:YES forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
            FBTMobileConfigResponseCaptureInstall();
            FBTInstallMobileConfigDebugUIBootstrap();
        }
        NSString *reason = nil;
        BOOL ok = FBTMCNativeProbeSetEnabled(key, control.isOn, &reason);
        if (!ok) {
            control.on = NO;
            [self showDiagnosticInfo:@"Probe indisponível" message:reason ?: @"Hook não validado para a imagem carregada."];
        }
    }
    [self refreshReport];
}
- (BOOL)ensureFetcherReady {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        [FBTDefaults setBool:YES forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
        FBTMobileConfigResponseCaptureInstall();
        FBTInstallMobileConfigDebugUIBootstrap();
    }
    NSDictionary *native = FBTMobileConfigFetcherCaptureStatus();
    if (FBTMCNativeProbeIsEnabled(FBTMCNativeProbeFetcherKey) && [native[@"native_mc_fetcher_installed"] boolValue])
        return YES;
    NSString *reason = nil;
    if (!FBTMCNativeProbeSetEnabled(FBTMCNativeProbeFetcherKey, YES, &reason)) {
        [self showDiagnosticInfo:@"Probe indisponível" message:reason ?: @"Não foi possível interceptar asyncFetch com ABI validada."];
        [self refreshReport];
        return NO;
    }
    return YES;
}
- (void)armExperiment:(id)sender {
    if (![self ensureFetcherReady]) return;
    FBTMobileConfigArmEmployeeExperiment(self.selectedProfile == 1);
    NSDictionary *pending = FBTMobileConfigEmployeeExperimentStatus();
    if (![pending[@"armed"] boolValue]) {
        [self showDiagnosticInfo:@"Falha no armamento" message:@"A sessão não aceitou o experimento. Verifique o log."];
    } else {
        NSString *name = self.selectedProfile == 1 ? @"B · is_employee=true" : @"A · request original";
        [self showDiagnosticInfo:@"Experimento armado"
                         message:[NSString stringWithFormat:@"%@. Válido por 120 segundos, somente para o próximo POST QE-info. Agora execute a ação nativa de fetch. O botão NÃO dispara uma requisição.", name]];
    }
    [self refreshReport];
}
- (void)cancelExperiment:(id)sender {
    FBTMobileConfigCancelEmployeeExperiment();
    FBTMobileConfigCancelFullQEInfoRequest();
    FBTEmployeeCancelTWProbe();
    [self refreshReport];
}
- (void)armFullQE:(id)sender {
    if (![self ensureFetcherReady]) return;
    FBTMobileConfigArmFullQEInfoRequest();
    [self showDiagnosticInfo:@"QE completo armado"
                     message:@"O próximo POST QE-info receberá as opções completas. Identidade e token permanecem inalterados. Expira em 120 segundos."];
    [self refreshReport];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 3) {
        NSString *detail = self.rows[path.section][path.row];
        [self showDiagnosticInfo:@"Detalhes do diagnóstico" message:detail];
        return;
    }
    if (path.section != 4) return;
    if (path.row == 0) [self.navigationController pushViewController:[[FBTNetworkInspectorViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    else if (path.row == 1) [self.navigationController pushViewController:[[FBTLocalConfigViewController alloc] initWithSearchQuery:@""] animated:YES];
    else if (path.row == 2) [self.navigationController pushViewController:[[FBTNativeTraceViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    else if (path.row == 3) UIPasteboard.generalPasteboard.string = FBTMobileConfigFetchDiagnosticsJSON();
    else if (path.row == 4) [self shareReport];
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


