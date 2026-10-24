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
#import "../Runtime/FBTMCNativeSessionProbes.h"
extern void FBTInitEmployeeGroup(void);

@interface FBTNamesDiagnosticsViewController ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSDictionary *report;
@property (nonatomic, copy) NSArray<NSString *> *controlIDs;
@property (nonatomic, copy) NSArray<NSDictionary *> *history;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *rows;
@end

@implementation FBTNamesDiagnosticsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Fetch e contexto QE";
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
    BOOL installed = [transport[@"native_mc_fetcher_installed"] boolValue] && [transport[@"simple_callback_hooks_installed"] boolValue] &&
        [self.report[@"native_session_probes"][@"fetcher_session_enabled"] boolValue] &&
        [self.report[@"native_session_probes"][@"tigon_session_enabled"] boolValue];
    NSString *readiness = !enabled ? @"Captura pausada" : installed ? @"Captura nativa pronta" : @"Captura incompleta — verifique os hooks";
    NSString *status = [NSString stringWithFormat:@"%@\nPedidos nativos: %@ · conclusões: %@\nCorrelações de transporte: %@\n%@%@",
        readiness, transport[@"native_mc_requests"] ?: @0, transport[@"native_mc_responses"] ?: @0,
        transport[@"native_tigon_correlations"] ?: @0,
        [transport[@"native_mc_fetcher_installed"] boolValue] ? @"" : (transport[@"native_mc_fetcher_failure"] ?: @"Fetcher não instalado. "),
        [transport[@"simple_callback_hooks_installed"] boolValue] ? @"" : (transport[@"simple_callback_failure"] ?: @"Callbacks não instalados.")];
    NSString *requestText = request ? [NSString stringWithFormat:
        @"Pedido %@ · %@ · %@\nPerfil: %@ · aplicado: %@ · motivo: %@\nAntes (somente booleanos): %@\nDepois (somente booleanos): %@\nResumo: %@",
        request[@"request_id"], request[@"request_method"] ?: @"?", request[@"time_utc"] ?: @"",
        request[@"experiment_profile"] ?: @"native",
        request[@"metadata_profile_applied"] ?: @NO, request[@"metadata_profile_reason"] ?: @"not_armed",
        request[@"request_protocol_options_before"] ?: @{},
        request[@"request_protocol_options_after"] ?: @{},
        request[@"request_parameter_summary"] ?: @""] : @"Aguardando tentativa pelo menu nativo.";
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
    NSString *serviceText = [NSString stringWithFormat:@"Serviço/fetcher do pedido QE:\n%@\n\nLeituras do seletor de autenticação:\n%@\n\nOs identificadores são efêmeros deste processo. Igualdade compara observações de ponteiros; não demonstra sessão, ator autorizado ou vida útil do objeto. Leituras do construtor são globais ao processo, sem vínculo comprovado com este pedido.",
        request[@"tigon_service_snapshot"] ?: @"não observado — arme o probe nativo do fetcher",
        request[@"auth_validation_read_snapshot"] ?: @"não observadas"];
    NSMutableArray *valueServices = [NSMutableArray array];
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        if (![event[@"process_session_id"] isEqual:process] ||
            ![event[@"event"] isEqual:@"native_mc_fetch_started"] ||
            ![@[@"mobileconfig", @"mobileconfigsessionless"] containsObject:event[@"capture_reason"] ?: @""]) continue;
        [valueServices addObject:[NSString stringWithFormat:@"%@ · pedido %@ · %@\n%@", event[@"capture_reason"],
            event[@"request_id"], event[@"time_utc"] ?: @"", event[@"tigon_service_snapshot"] ?: @"serviço não observado"]];
        if (valueServices.count == 4) break;
    }
    NSString *comparisonText = valueServices.count ? [valueServices componentsJoinedByString:@"\n\n"] : @"Nenhum fetch de valores/sessionless observado nesta captura. Reproduza cada ação separadamente com os probes armados.";
    NSMutableArray *uiContexts = [NSMutableArray array];
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        if (![event[@"process_session_id"] isEqual:process] || ![event[@"event"] isEqual:@"mc_ui_service_snapshot"]) continue;
        [uiContexts addObject:[NSString stringWithFormat:@"%@ · %@\n%@", event[@"ui_context_kind"] ?: @"?",
            event[@"time_utc"] ?: @"", event[@"tigon_service_snapshot"] ?: @"não observado"]];
        if (uiContexts.count == 6) break;
    }
    NSString *contextText = uiContexts.count ? [uiContexts componentsJoinedByString:@"\n\n"] : @"Contextos da UI ainda não observados. Com o probe do fetcher armado, reabra MobileConfig e selecione um item. A captura exige o getter e o layout da imagem verificada.";
    NSMutableArray *controls = [@[@"Iniciar nova captura", @"Armar probes desta sessão", @"Pausar captura", @"Copiar relatório JSON", @"Abrir mapa local", @"Cancelar testes temporários"] mutableCopy];
    NSMutableArray *commands = [@[@"start", @"probes", @"pause", @"copy", @"local", @"cancel"] mutableCopy];
    if (FBTQEInvasiveHooksAllowed()) {
        [controls addObjectsFromArray:@[@"LAB: próximo pedido QE original", @"LAB: próximo pedido QE + is_employee=true", @"LAB: QE Full Metadata (1 pedido / 120 s)", @"LAB: tw_is_employee=true por 120 s",
            [NSString stringWithFormat:@"LAB: Employee local %@", [FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ? @"ON" : @"OFF"]]];
        [commands addObjectsFromArray:@[@"A", @"B", @"full_qe", @"tw", @"employee"]];
    }
    self.controlIDs = commands;
    self.rows = @[controls,
        @[status, [NSString stringWithFormat:@"%@\n\n%@\n\n%@", advice[@"title"], advice[@"explanation"], advice[@"next_step"]]],
        @[requestText, result, localState, interpretation, authText, serviceText, contextText, comparisonText, identityText], historyText,
        @[@"Inicie uma captura e mantenha as opções locais constantes. Em Configurações da tweak, arme os dois probes nativos de sessão (fetcher e callbacks Tigon). Reproduza uma ação de cada vez: consulta QE, Force name download e refresh de valores. Cada pedido tem ID, horário, serviço observado e resultado próprios. Os probes são experimentais e exigem UUID/slot compatível; reiniciar desarma.\n\nPara confirmar o contexto enviado na rede, use o proxy Whitehat com sua CA correspondente; veja docs/qe-proxy-whitehat.md. A captura externa se alinha por ação/horário, não ganha associação exata à sessão automaticamente. Perfil LAB QE Full Metadata: arme por até 120 s, execute uma única ação nativa, compare request_protocol_options_before/after com protocol_options do proxy. Nunca interpreta HTTP 400 como sucesso. Exporte o JSON do painel e o JSONL sanitizado do proxy.\n\nNão altere employee/overrides para estabelecer a linha de base. OAuth presente, HTTP 200 em valores e mesmo serviço não comprovam elegibilidade QE. O predicado privado do servidor pode continuar desconhecido."]];
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
    if (path.row >= self.controlIDs.count) return;
    NSString *command = self.controlIDs[path.row];
    if ([command isEqual:@"start"]) {
        [FBTDefaults setBool:YES forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
        FBTMobileConfigResponseCaptureInstall();
        FBTInstallMobileConfigDebugUIBootstrap();
        FBTInitEmployeeGroup();
        FBTInstallMobileConfigRuntime();
        FBTMobileConfigCancelEmployeeExperiment();
        FBTMobileConfigCancelFullMetadataExperiment();
        FBTEmployeeDiagnosticsReset();
        FBTMobileConfigFetchDiagnosticsReset();
        FBTMobileConfigResponseCaptureArm(@"force_name_download");
    } else if ([command isEqual:@"probes"]) {
        NSString *reason = nil;
        FBTMCNativeProbeSetEnabled(FBTMCNativeProbeFetcherKey, YES, &reason);
        FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, &reason);
    } else if ([command isEqual:@"pause"]) {
        FBTMobileConfigFetchDiagnosticsRecord(@"capture_paused", @{});
        [FBTDefaults setBool:NO forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
        FBTMCNativeProbeDisableAll();
        FBTMobileConfigResponseCaptureDisarm();
        FBTMobileConfigCancelEmployeeExperiment();
        FBTMobileConfigCancelFullMetadataExperiment();
        FBTEmployeeCancelTWProbe();
    } else if ([command isEqual:@"copy"]) [UIPasteboard generalPasteboard].string = FBTMobileConfigFetchDiagnosticsJSON();
    else if ([command isEqual:@"local"]) [self.navigationController pushViewController:[[FBTLocalConfigViewController alloc] initWithSearchQuery:@""] animated:YES];
    else if (FBTQEInvasiveHooksAllowed() && ([command isEqual:@"A"] || [command isEqual:@"B"])) FBTMobileConfigArmEmployeeExperiment([command isEqual:@"B"]);
    else if (FBTQEInvasiveHooksAllowed() && [command isEqual:@"full_qe"]) {
        if (!FBTMobileConfigArmFullMetadataExperiment()) {
            UIAlertController *warning = [UIAlertController alertControllerWithTitle:@"Perfil LAB indisponível"
                message:@"É necessário build LAB, diagnóstico ativo e hook fetcher com ABI verificada. Nenhum pedido foi alterado."
                preferredStyle:UIAlertControllerStyleAlert];
            [warning addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:warning animated:YES completion:nil];
        } else {
            UIAlertController *ready = [UIAlertController alertControllerWithTitle:@"QE Full Metadata armado"
                message:@"O próximo POST mobileconfig_qe_info dentro de 120 s usará o perfil experimental se os nove campos forem válidos. Execute Force Name Download e confira o resultado real."
                preferredStyle:UIAlertControllerStyleAlert];
            [ready addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:ready animated:YES completion:nil];
        }
    }
    else if (FBTQEInvasiveHooksAllowed() && [command isEqual:@"tw"]) FBTEmployeeArmTWProbe();
    else if ([command isEqual:@"cancel"]) { FBTMobileConfigCancelEmployeeExperiment(); FBTMobileConfigCancelFullMetadataExperiment(); FBTEmployeeCancelTWProbe(); }
    else if (FBTQEInvasiveHooksAllowed() && [command isEqual:@"employee"]) {
        [FBTDefaults setBool:![FBTDefaults boolForKey:FBTKeyEmployeeEnabled] forKey:FBTKeyEmployeeEnabled];
        FBTInitEmployeeGroup();
    }
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


