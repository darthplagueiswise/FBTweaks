#import "../UI/FBTUIKit26LiquidGlass.h"
#import "FBTQERequestOptionsViewController.h"
#import "../FBTDefaults.h"
#import "../Runtime/FBTQERequestOptions.h"
#import "../Runtime/FBTMobileConfigDebugUIHooks.h"
#import "../Runtime/FBTMobileConfigFetchDiagnostics.h"
#import "../Runtime/FBTMCNativeSessionProbes.h"

@implementation FBTQERequestOptionsViewController
- (NSArray<NSString *> *)optionKeys {
    return @[@"with_universe_params", @"with_current_experiment_group",
        @"with_only_current_experiment_group", @"with_experiments", @"with_params",
        @"with_groups", @"with_group_params", @"with_gatekeepers", @"needs_name", @"skip_qe"];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    FBTUIKit26ConfigureViewController(self);
    if ([self isKindOfClass:UITableViewController.class]) FBTUIKit26ConfigureTableView(((UITableViewController *)self).tableView); self.title = @"Opções dos pedidos QE";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    FBTInstallMobileConfigDebugUIBootstrap(); [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : section == 1 ? self.optionKeys.count : section == 2 ? 2 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"Aplicação nesta sessão", @"Valores do pedido nativo", @"Predefinições", @"Estado"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Desligado preserva o pedido nativo. Ligado aplica os dez valores abaixo. Os ajustes duram até reiniciar o app. Pausar a captura ou cancelar testes também desliga a aplicação.";
    if (section == 1) return @"ON envia true; OFF envia false. Aplicam-se somente a POST mobileconfig_qe_info. Valores, sessão, token, device_id, queries e api_version permanecem nativos. Alterar needs_name ou o conteúdo solicitado pode impedir o parser de nomes de encontrar os dados esperados.";
    if (section == 2) return @"As predefinições mudam os switches e preservam o estado de aplicação. Nenhuma delas dispara uma requisição.";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    FBTUIKit26ConfigureTableCell(cell);
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    NSDictionary *state = FBTQERequestOptionsSnapshot();
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (path.section <= 1) {
        UISwitch *toggle = [UISwitch new];
        toggle.tag = path.section == 0 ? path.row : 100 + path.row;
        if (path.section == 0) {
            cell.textLabel.text = path.row == 0 ? @"Aplicar opções personalizadas" : @"Todos os pedidos QE-info";
            cell.detailTextLabel.text = path.row == 1 ? @"ON: consultas de configs/params e nomes. OFF: somente Force Name Download." : nil;
            toggle.on = [state[path.row == 0 ? @"enabled" : @"all_qe_info"] boolValue];
        } else {
            NSString *key = self.optionKeys[path.row]; cell.textLabel.text = key;
            cell.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote] scaledFontForFont:[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]];
            toggle.on = [state[@"values"][key] boolValue];
        }
        [toggle addTarget:self action:@selector(optionChanged:) forControlEvents:UIControlEventValueChanged];
        toggle.accessibilityLabel = cell.textLabel.text;
        toggle.accessibilityIdentifier = path.section == 1 ? [@"fbtweak.qe." stringByAppendingString:self.optionKeys[path.row]] : path.row == 0 ? @"fbtweak.qe.enabled" : @"fbtweak.qe.all";
        cell.accessoryView = toggle;
    } else if (path.section == 2) {
        cell.textLabel.text = path.row == 0 ? @"Restaurar opções nativas de nomes" : @"Todos with_* = true; needs_name = true; skip_qe = false";
        cell.textLabel.textColor = UIColor.systemBlueColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        NSDictionary *hooks = FBTMobileConfigDebugUIHookStatus();
        BOOL fetcher = [FBTMCNativeProbeStatus()[@"fetcher_session_enabled"] boolValue];
        cell.textLabel.text = [NSString stringWithFormat:@"Aplicação: %@\nFetcher armado: %@\nAção Force Name verificada: %@\n%@",
            [state[@"enabled"] boolValue] ? @"ON" : @"OFF", fetcher ? @"sim" : @"não",
            [hooks[@"force_name_action_hook_available"] boolValue] ? @"sim" : @"não",
            [hooks[@"force_name_action_hook_available"] boolValue] ? @"" : hooks[@"force_name_action_hook_failure"] ?: @""];
        cell.detailTextLabel.text = @"Confirme qe_request_options_state=applied e os valores no histórico do pedido. Nenhum resultado de sucesso é forçado. A aceitação pelo servidor continua sendo medida pela resposta real.";
    }
    return cell;
}
- (void)optionChanged:(UISwitch *)toggle {
    if (toggle.tag == 0) {
        BOOL enabled = toggle.on;
        if (enabled) {
            [FBTDefaults setBool:YES forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
            NSString *reason = nil;
            enabled = FBTMCNativeProbeSetEnabled(FBTMCNativeProbeFetcherKey, YES, &reason);
            FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, nil);
            FBTInstallMobileConfigDebugUIBootstrap();
            if (!enabled) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Fetcher indisponível" message:reason preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }
        FBTQERequestOptionsSetEnabled(enabled);
    } else if (toggle.tag == 1) FBTQERequestOptionsSetAllQE(toggle.on);
    else if (toggle.tag >= 100 && toggle.tag < 110)
        FBTQERequestOptionsSetValue(self.optionKeys[toggle.tag - 100], toggle.on);
    FBTMobileConfigFetchDiagnosticsRecord(@"qe_request_options_edited", @{@"message": @"session_only_profile_changed"});
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 2) { FBTQERequestOptionsReset(path.row == 1); [self.tableView reloadData]; }
}
@end
