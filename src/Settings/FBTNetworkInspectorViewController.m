#import "../UI/FBTUIKit26LiquidGlass.h"
#import "FBTNetworkInspectorViewController.h"
#import "../Runtime/FBTNetworkInspectorStore.h"
#import "../Runtime/FBTMCNativeSessionProbes.h"
#import "../Runtime/FBTMobileConfigResponseCapture.h"
#import "../Runtime/FBTMobileConfigFetchDiagnostics.h"
#import "../FBTDefaults.h"

static NSString *FBTNIJSON(NSDictionary *record) {
    if (![record isKindOfClass:NSDictionary.class]) return @"{}";
    NSData *data = [NSJSONSerialization dataWithJSONObject:record
        options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

@interface FBTNetworkInspectorDetailController : UIViewController
@property (nonatomic, copy) NSString *recordID;
@property (nonatomic, strong) UITextView *text;
@property (nonatomic, strong) UISegmentedControl *segments;
@end

@implementation FBTNetworkInspectorDetailController
- (instancetype)initWithRecordID:(NSString *)identifier {
    if ((self = [super init])) self.recordID = [identifier copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    FBTUIKit26ConfigureViewController(self);
    if ([self isKindOfClass:UITableViewController.class]) FBTUIKit26ConfigureTableView(((UITableViewController *)self).tableView);
    self.title = @"Request / Response";
    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[@"Resumo", @"Request", @"HTTP", @"Nativo"]];
    tabs.selectedSegmentIndex = 0;
    [tabs addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = tabs;
    self.segments = tabs;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *view = [UITextView new];
    view.editable = NO;
    view.selectable = YES;
    view.backgroundColor = UIColor.systemBackgroundColor;
    view.textColor = UIColor.labelColor;
    view.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12]
    ]];
    self.text = view;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(exportSelected)];
    [self refresh];
}
- (void)refresh {
    NSDictionary *record = FBTNetworkInspectorRecordWithID(self.recordID);
    NSDictionary *visible = record;
    switch (self.segments.selectedSegmentIndex) {
        case 1: visible = @{@"request_id": record[@"request_id"] ?: @0,
                            @"purpose": record[@"purpose"] ?: @"",
                            @"source": record[@"request_source"] ?: @"",
                            @"method": record[@"method"] ?: @"",
                            @"host": record[@"inspector_raw_host"] ?: @"",
                            @"path": record[@"inspector_raw_path"] ?: @"",
                            @"query": record[@"inspector_query"] ?: @"",
                            @"headers_known": record[@"known_request_headers"] ?: @{},
                            @"parameter_pairs": record[@"request_parameter_pairs"] ?: @[],
                            @"capture_state": record[@"request_parameter_capture"] ?: @"not_observed"};
                break;
        case 2: visible = @{@"http_status": record[@"tigon_http_status"] ?: @0,
                            @"source": record[@"http_response_source"] ?: @"not_observed",
                            @"status_source": record[@"tigon_status_source"] ?: @"not_observed",
                            @"body": record[@"http_response_body"] ?: @{}};
                break;
        case 3: visible = @{@"success": record[@"native_transport_success"] ?: @NO,
                            @"status": record[@"native_completion_status"] ?: @0,
                            @"body_source": record[@"native_body_source"] ?: @"not_observed",
                            @"duration_ms": record[@"duration_ms"] ?: @0,
                            @"body": record[@"native_completion_body"] ?: @{}};
                break;
        default: break;
    }
    NSString *json = FBTNIJSON(visible);
    if (json.length > 160000) {
        // Prevent a multi-MB NSData->UITextView allocation; use Export for exact bytes.
        self.text.text = [[json substringToIndex:160000]
            stringByAppendingString:@"\n\n[PREVIEW TRUNCATED — Exportar para obter os bytes Base64 completos]"];
    } else self.text.text = json;
}
- (void)exportSelected {
    NSDictionary *record = FBTNetworkInspectorRecordWithID(self.recordID);
    NSURL *url = [[FBTNetworkInspectorExportURLs() filteredArrayUsingPredicate:
                   [NSPredicate predicateWithBlock:^BOOL(NSURL *candidate, __unused NSDictionary *bindings) {
                       return [candidate.lastPathComponent isEqualToString:[self.recordID stringByAppendingString:@".json"]];
                   }]] firstObject];
    if (!record.count || !url) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Exportar captura integral?"
        message:@"O JSON contém parâmetros, headers conhecidos e corpos HTTP não mascarados; pode conter tokens e identificadores privados. Compartilhe somente em local confiável."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Exportar" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act) {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
        [self presentViewController:share animated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@interface FBTNetworkInspectorViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *captures;
@property (nonatomic, strong) NSTimer *reloadTimer;
@end

@implementation FBTNetworkInspectorViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    FBTUIKit26ConfigureViewController(self);
    if ([self isKindOfClass:UITableViewController.class]) FBTUIKit26ConfigureTableView(((UITableViewController *)self).tableView);
    self.title = @"Inspetor de rede";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(exportAll)];
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reloadCaptures) forControlEvents:UIControlEventValueChanged];
    [self reloadCaptures];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.reloadTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.reloadTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(__unused NSTimer *t) {
        [weakSelf reloadCaptures];
    }];
    [self reloadCaptures];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.reloadTimer invalidate];
    self.reloadTimer = nil;
}
- (void)dealloc { [_reloadTimer invalidate]; }
- (void)reloadCaptures {
    self.captures = FBTNetworkInspectorSummaries();
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 4 : self.captures.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Captura local MobileConfig / QE-info" :
        [NSString stringWithFormat:@"Capturas (%lu)", (unsigned long)self.captures.count];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"O probe usa os slots Tigon e asyncFetch originais, validados por UUID. Sem CA, VPN, proxy ou computador. Dados completos ficam apenas no sandbox do Facebook com proteção de arquivo iOS; a captura não reinicia automaticamente.";
    return @"Corpos recebidos no Tigon ficam separados do retorno convertido pelo aplicativo. O corpo e os parâmetros podem conter credenciais privadas: use Exportar conscientemente.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FBTInspectorRow"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FBTInspectorRow"];
    FBTUIKit26ConfigureTableCell(cell);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    if (indexPath.section == 0) {
        BOOL armed = FBTNetworkInspectorIsCapturing();
        NSArray *titles = @[
            armed ? @"Parar captura" : @"Iniciar captura completa (local)",
            @"Estado dos hooks Tigon / fetcher",
            @"Abrir diagnóstico MobileConfig existente",
            @"Apagar todas as capturas locais"
        ];
        NSArray *subtitles = @[
            armed ? @"Ativa nesta sessão. Toque para parar; os arquivos persistem até apagar." :
                    @"Arma hooks com validação de UUID e grava dados de requisição/resposta.",
            FBTNIJSON(FBTMCNativeProbeStatus()),
            @"Visualizar os eventos de fetch, QE-info e callbacks já instrumentados.",
            @"Apaga definitivamente os JSONs protegidos neste sandbox."
        ];
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = subtitles[indexPath.row];
    } else {
        NSDictionary *record = self.captures[indexPath.row];
        NSNumber *status = record[@"http_status"] ?: @0;
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · HTTP %@",
                               record[@"purpose"] ?: @"unknown", status];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"#%@ · %@ · %@",
                                     record[@"request_id"] ?: @0,
                                     record[@"created_at"] ?: @"", record[@"stage"] ?: @""];
    }
    return cell;
}
- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)startCapture {
    [FBTDefaults setBool:YES forKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
    // Both hooks are session-only and installed via UUID/slot checks, not __TEXT patches.
    NSString *tigonError = nil, *fetchError = nil;
    BOOL tigon = FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, &tigonError);
    BOOL fetcher = FBTMCNativeProbeSetEnabled(FBTMCNativeProbeFetcherKey, YES, &fetchError);
    if (!fetcher || !tigon) {
        FBTNetworkInspectorSetCapturing(NO);
        [self alert:@"Captura indisponível" message:[NSString stringWithFormat:
            @"Fetcher: %@\nTigon: %@\n\nNão afirmamos capturar tráfego enquanto os hooks não estiverem operacionais.",
            fetchError ?: @"?", tigonError ?: @"?"]];
        [self reloadCaptures];
        return;
    }
    FBTNetworkInspectorSetCapturing(YES);
    [self alert:@"Network Inspector ativo" message:
        @"Abra Internal Settings → MobileConfig → Advanced Settings → Force Name Download e também o refresh de valores. As requisições e respostas observadas serão gravadas no iPhone. Nenhum retorno é alterado."];
    [self reloadCaptures];
}
- (void)toggleCapture {
    if (FBTNetworkInspectorIsCapturing()) {
        FBTNetworkInspectorSetCapturing(NO);
        [self reloadCaptures];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Inspeção HTTP local"
        message:@"Capturaremos pares completos da requisição e respostas recebidas nos hooks MobileConfig/Tigon. Os JSONs podem conter tokens, cookies, IDs e informações privadas. A coleta é apenas nesta sessão e os dados não são enviados automaticamente."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Iniciar captura" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
        [self startCapture];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)exportAll {
    NSArray<NSURL *> *urls = FBTNetworkInspectorExportURLs();
    if (!urls.count) { [self alert:@"Sem capturas" message:@"Inicie a captura e execute uma operação MobileConfig."]; return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Exportar JSONs integrais?"
        message:[NSString stringWithFormat:@"%lu arquivo(s). Podem conter credenciais e dados privados. Os arquivos não são anonimizados; exporte apenas para um destino confiável.", (unsigned long)urls.count]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Exportar" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act) {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
        share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
        [self presentViewController:share animated:YES completion:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)clearRecords {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Apagar capturas?"
        message:@"Apaga todos os arquivos locais, inclusive os corpos HTTP, sem possibilidade de desfazer."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Apagar" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act) {
        FBTNetworkInspectorClear();
        [self reloadCaptures];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        NSString *recordID = self.captures[indexPath.row][@"record_id"];
        if (recordID.length) [self.navigationController pushViewController:
            [[FBTNetworkInspectorDetailController alloc] initWithRecordID:recordID] animated:YES];
        return;
    }
    switch (indexPath.row) {
        case 0: [self toggleCapture]; break;
        case 1: [self alert:@"Hooks atuais" message:FBTNIJSON(FBTMCNativeProbeStatus())]; break;
        case 2: [self alert:@"Diagnóstico nativo" message:@"Acesse FBTweak → Diagnóstico do download de nomes. O Network Inspector registra seus próprios JSONs integrais, separados do log sanitizado."]; break;
        case 3: [self clearRecords]; break;
    }
}
@end
