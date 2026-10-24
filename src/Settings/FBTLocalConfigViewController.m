#import "../UI/FBTUIKit26LiquidGlass.h"
#import "FBTLocalConfigViewController.h"
#import "../Runtime/FBTMobileConfigFetchDiagnostics.h"
#import "../Runtime/FBTLocalConfigCatalog.h"
#import "../Runtime/FBTMCOverridesFile.h"
#import "../Runtime/FBTMobileConfigValueReader.h"
#include <errno.h>
#include <math.h>
#include <stdlib.h>

@interface FBTLocalConfigViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *initialQuery;
@property (nonatomic, strong) NSDictionary *configuration;
@property (nonatomic, copy) NSArray *allRows;
@property (nonatomic, copy) NSArray *rows;
@property (nonatomic, copy) NSDictionary *values;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic) NSUInteger searchGeneration;
@property (nonatomic) NSUInteger readGeneration;
@property (nonatomic, copy) NSDictionary *readings;
@property (nonatomic) NSUInteger inspectedCount;
@end

@implementation FBTLocalConfigViewController
- (instancetype)initWithSearchQuery:(NSString *)query {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) _initialQuery = [query copy] ?: @"";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    FBTUIKit26ConfigureViewController(self);
    if ([self isKindOfClass:UITableViewController.class]) FBTUIKit26ConfigureTableView(((UITableViewController *)self).tableView);
    self.title = self.configuration ? self.configuration[@"name"] : @"MobileConfig local";
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"Config, parâmetro ou ID";
    self.navigationItem.searchController = self.search;
    self.search.searchBar.text = self.initialQuery;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 84;
    if (self.configuration) {
        self.allRows = self.configuration[@"params"];
        [self reloadValues];
        [self updateSearchResultsForSearchController:self.search];
        self.refreshControl = [UIRefreshControl new];
        [self.refreshControl addTarget:self action:@selector(refreshEffectiveValues) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareValues)];
    } else {
        self.navigationItem.prompt = @"Lendo os mapas do aplicativo…";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSArray *configurations = [FBTLocalConfigCatalog configurations];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.allRows = configurations;
                [self updateSearchResultsForSearchController:self.search];
            });
        });
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.configuration) [self refreshEffectiveValues];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    ++self.readGeneration;
    [self.refreshControl endRefreshing];
}
- (void)refreshEffectiveValues {
    // Local inspection only; does not initiate server fetch or mutate MobileConfig.
    if (self.configuration) {
        FBTMobileConfigFetchDiagnosticsRecord(@"mc_source_inspection_started", @{
            @"mc_config_name": self.configuration[@"name"] ?: @"unknown",
            @"mc_config_key": self.configuration[@"id"] ?: @(-1)
        });
    }
    [self reloadValues];
    self.readings = @{};
    self.inspectedCount = 0;
    NSUInteger generation = ++self.readGeneration;
    [self readBatchAtIndex:0 generation:generation];
}
- (void)readBatchAtIndex:(NSUInteger)start generation:(NSUInteger)generation {
    if (generation != self.readGeneration) return;
    NSArray *parameters = self.configuration[@"params"];
    NSMutableDictionary *readings = [self.readings mutableCopy] ?: [NSMutableDictionary dictionary];
    NSUInteger end = MIN(start + 6, parameters.count);
    for (NSUInteger i = start; i < end; ++i) {
        NSDictionary *parameter = parameters[i];
        readings[[parameter[@"id"] stringValue]] = FBTMobileConfigInspectParameter(self.configuration, parameter);
    }
    self.inspectedCount = end;
    self.readings = readings;
    self.navigationItem.prompt = [NSString stringWithFormat:@"%@ · %lu/%lu leituras", self.configuration[@"scope"], (unsigned long)end, (unsigned long)parameters.count];
    [self.tableView reloadData];
    if (end < parameters.count) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self readBatchAtIndex:end generation:generation]; });
    } else [self.refreshControl endRefreshing];
}
- (NSString *)valueDetailsForParameter:(NSDictionary *)parameter {
    NSString *pid = [parameter[@"id"] stringValue], *type = parameter[@"type"];
    NSString *fileValue = self.values[pid];
    NSDictionary *reading = self.readings[pid];
    NSString *state = fileValue ? [@"Override no arquivo: " stringByAppendingString:fileValue] : @"SYS (sem override no arquivo)";
    if (![reading[@"available"] boolValue]) return [NSString stringWithFormat:@"%@\n%@", state, reading[@"reason"] ?: @"Consultando o leitor nativo…"];
    NSString *systemText = [reading[@"system_available"] boolValue] ? FBTMobileConfigValueText(reading[@"system_value"], type) : @"não confirmado";
    return [NSString stringWithFormat:@"%@\nEm uso: %@ · SYS: %@\nOrigem SYS: %@ · Em uso: %@\n%@",
        state, FBTMobileConfigValueText(reading[@"effective_value"], type),
        systemText, reading[@"source"], reading[@"effective_source"], reading[@"source_hint"] ?: @""];
}
- (void)shareValues {
    NSMutableArray *parameters = [NSMutableArray array];
    for (NSDictionary *parameter in self.configuration[@"params"]) {
        NSString *pid = [parameter[@"id"] stringValue];
        [parameters addObject:@{@"parameter": parameter, @"file_override": self.values[pid] ?: NSNull.null,
            @"reading": self.readings[pid] ?: @{@"available": @NO, @"reason": @"Leitura ainda não executada"}}];
    }
    NSDictionary *report = @{@"schema_version": @1, @"configuration_id": self.configuration[@"id"],
        @"configuration": self.configuration[@"name"], @"scope": self.configuration[@"scope"],
        @"map": self.configuration[@"source"], @"exported_at": @([NSDate date].timeIntervalSince1970), @"parameters": parameters};
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"fbt_mc_values_%@_%@.json", self.configuration[@"id"], NSUUID.UUID.UUIDString]]];
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        [self message:error.localizedDescription ?: @"Não foi possível exportar." title:@"Falha na exportação"]; return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}
- (void)reloadValues {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSString *prefix = [NSString stringWithFormat:@"%@:", self.configuration[@"id"]];
    NSDictionary *all = [FBTMCOverridesFile loadOverrides];
    for (NSString *key in all) {
        if (![key hasPrefix:prefix] || ![all[key] isKindOfClass:[NSArray class]]) continue;
        for (id entry in all[key]) {
            if (![entry isKindOfClass:[NSString class]]) continue;
            NSRange first = [entry rangeOfString:@":"];
            if (first.location == NSNotFound) continue;
            NSRange second = [entry rangeOfString:@":" options:0 range:NSMakeRange(first.location + 1, [entry length] - first.location - 1)];
            if (second.location == NSNotFound) continue;
            NSString *value = [entry substringFromIndex:second.location + 1];
            values[[entry substringToIndex:first.location]] = [value hasPrefix:@" "] ? [value substringFromIndex:1] : value;
        }
    }
    self.values = values;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = [controller.searchBar.text lowercaseString] ?: @"";
    NSArray *source = self.allRows ?: @[];
    BOOL params = self.configuration != nil;
    NSUInteger generation = ++self.searchGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *result = [NSMutableArray array];
        for (NSDictionary *row in source) {
            NSString *label = [NSString stringWithFormat:@"%@ %@", row[@"id"], row[@"name"]];
            BOOL matches = !query.length || [label.lowercaseString containsString:query];
            if (!matches && !params) {
                for (NSDictionary *param in row[@"params"]) {
                    NSString *p = [NSString stringWithFormat:@"%@:%@ %@", row[@"id"], param[@"id"], param[@"name"]];
                    if ([p.lowercaseString containsString:query]) { matches = YES; break; }
                }
            }
            if (matches) [result addObject:row];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.searchGeneration) return;
            self.rows = result;
            self.navigationItem.prompt = [NSString stringWithFormat:@"%lu de %lu %@", (unsigned long)result.count,
                (unsigned long)source.count, params ? @"parâmetros" : @"configurações dos mapas locais"];
            [self.tableView reloadData];
        });
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.configuration ? @"Em uso é o retorno atual do leitor nativo. SYS ignora os overrides durante uma leitura isolada e mostra a origem informada pelo app, que pode ser servidor, cache ou default. Indisponível nunca significa false. Puxe para atualizar; compartilhe para exportar os valores. Alterações no arquivo precisam de reinício para serem reimportadas."
        : @"Catálogo dos mapas v2 do aplicativo, incluindo Page/Admin ID e React Native. A busca encontra nomes e IDs de configurações e parâmetros.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"local"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"local"];
    FBTUIKit26ConfigureTableCell(cell);
    NSDictionary *row = self.rows[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@: %@", row[@"id"], row[@"name"]];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    if (self.configuration) {
        NSString *value = self.values[[row[@"id"] stringValue]];
        NSString *details = [self valueDetailsForParameter:row];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", row[@"type"], details.length > 600 ? [[details substringToIndex:600] stringByAppendingString:@"…"] : details];
        cell.accessibilityValue = details;
        cell.accessoryType = value ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu parâmetros", row[@"scope"], (unsigned long)[row[@"params"] count]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)message:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)save:(NSString *)value parameter:(NSDictionary *)parameter {
    NSError *error = nil;
    BOOL ok = [FBTMCOverridesFile setValueText:value forConfigID:[self.configuration[@"id"] integerValue]
        paramIdx:[parameter[@"id"] integerValue] configName:self.configuration[@"name"] paramName:parameter[@"name"] error:&error];
    if (!ok) { [self message:error.localizedDescription ?: @"Não foi possível gravar o arquivo." title:@"Alteração não gravada"]; return; }
    [self refreshEffectiveValues];
    [self message:[NSString stringWithFormat:@"%@\n\nEncerre e reabra o Facebook para reimportar os overrides.", [FBTMCOverridesFile path]] title:@"Override gravado"];
}
- (void)edit:(NSDictionary *)parameter {
    NSString *type = parameter[@"type"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:parameter[@"name"] message:type preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = self.values[[parameter[@"id"] stringValue]];
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.keyboardType = [type isEqualToString:@"string"] ? UIKeyboardTypeDefault : UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Gravar" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *value = alert.textFields.firstObject.text ?: @"";
        if (![type isEqualToString:@"string"]) {
            value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            const char *start = value.UTF8String; char *end = NULL; errno = 0;
            BOOL valid;
            if ([type isEqualToString:@"int64"]) { strtoll(start, &end, 10); valid = errno != ERANGE && end != start && *end == '\0'; }
            else { double number = strtod(start, &end); valid = errno != ERANGE && end != start && *end == '\0' && isfinite(number); }
            if (!valid) { [self message:@"Informe um número válido do tipo indicado." title:@"Valor inválido"]; return; }
        }
        [self save:value parameter:parameter];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.rows[indexPath.row];
    if (!self.configuration) {
        FBTLocalConfigViewController *child = [[FBTLocalConfigViewController alloc] initWithSearchQuery:@""];
        child.configuration = row;
        [self.navigationController pushViewController:child animated:YES];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:row[@"name"]
        message:[NSString stringWithFormat:@"%@: %@ · parâmetro %@ · %@\n%@", self.configuration[@"id"], self.configuration[@"name"], row[@"id"], row[@"type"], [self valueDetailsForParameter:row]]
        preferredStyle:UIAlertControllerStyleActionSheet];
    if ([row[@"type"] isEqualToString:@"bool"]) {
        for (NSString *value in @[@"true", @"false"]) [alert addAction:[UIAlertAction actionWithTitle:[@"Gravar " stringByAppendingString:value] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self save:value parameter:row]; }]];
    } else [alert addAction:[UIAlertAction actionWithTitle:@"Editar valor…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self edit:row]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restaurar SYS" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { [self save:nil parameter:row]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    alert.popoverPresentationController.sourceView = cell;
    alert.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}
@end

