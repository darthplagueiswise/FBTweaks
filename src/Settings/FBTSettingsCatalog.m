#import "FBTSettingsCatalog.h"
#import "../FBTDefaults.h"
#import "../Runtime/FBTMCNativeSessionProbes.h"

static NSString *Aliases(NSString *identifier) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names=@{
            FBTKeyMasterEnabled:@"Tweak ativada kill switch global",
            FBTKeyOpenThreeFingerDoubleTap:@"Toque duplo com três dedos",
            FBTKeyTestUserEnabled:@"Test user internal test user",
            FBTKeyKnownDogfoodEnabled:@"Dogfood conhecido",
            FBTKeyReactNativeInternalEnabled:@"React Native Internal Settings",
            FBTKeyBetaBuildEnabled:@"OS beta predicate",
            FBTKeyDogfoodSweepEnabled:@"Dogfood sweep runtime",
            FBTKeyInternalDebugSweepEnabled:@"Internal debug sweep runtime",
            FBTKeyInternalCImportsEnabled:@"C import Internal Settings",
            FBTKeyEasyGatingInternalEnabled:@"C import EasyGating internal",
            FBTKeyFloatingTabBarEnabled:@"Floating Tab Bar",
            FBTKeyMobileConfigRuntimeEnabled:@"MobileConfig runtime",
            FBTKeyMobileConfigNativeUIWarmupEnabled:@"Aquecer MobileConfig nativo",
            FBTKeyMobileConfigCaptureEnabled:@"Capturar leituras MobileConfig",
            FBTKeyMobileConfigFetchDiagnosticsEnabled:@"Log QE-info seguro",
            FBTMCNativeProbeTigonKey:@"Probe Tigon nativo sessão experimental",
            FBTMCNativeProbeFetcherKey:@"Probe fetch MobileConfig sessão experimental",
            FBTKeyMobileConfigOverridesEnabled:@"Aplicar overrides MobileConfig",
            FBTKeyRuntimeBoolBrowserEnabled:@"Runtime BOOL browser",
            @"ensure_mc_file":@"Criar mc_overrides.json nativo",
            @"qe_ab":@"A/B QE-info isolar refresh hash",
            @"clear":@"Limpar overrides runtime"
        };
    });
    return names[identifier] ?: @"";
}
static NSDictionary *Switch(NSString *title, NSString *subtitle, NSString *key, NSString *icon, BOOL restart) {
    return @{@"kind":@"switch",@"title":title,@"subtitle":subtitle,@"key":key,@"icon":icon,@"restart":@(restart),@"keywords":Aliases(key)};
}
static NSDictionary *Navigate(NSString *title, NSString *subtitle, NSString *dest, NSString *icon, NSString *keywords) {
    return @{@"kind":@"nav",@"title":title,@"subtitle":subtitle,@"dest":dest,@"icon":icon,@"keywords":keywords};
}
static NSDictionary *Action(NSString *title, NSString *subtitle, NSString *action, NSString *icon) {
    return @{@"kind":@"action",@"title":title,@"subtitle":subtitle,@"action":action,@"icon":icon,@"keywords":Aliases(action)};
}
static NSDictionary *Section(NSString *category, NSString *title, NSString *footer, NSArray *rows) {
    return @{@"category":category,@"title":title,@"footer":footer,@"rows":rows};
}
static NSString *Fold(NSString *text) {
    return [[(text ?: @"") stringByFoldingWithOptions:NSDiacriticInsensitiveSearch|NSCaseInsensitiveSearch
        locale:[NSLocale localeWithLocaleIdentifier:@"pt_BR"]] lowercaseString];
}
@implementation FBTSettingsCatalog
+ (NSArray<NSDictionary *> *)categories {
    return @[
        @{@"id":@"mobileconfig",@"title":@"MobileConfig",@"subtitle":@"Catálogo, valores e overrides",@"icon":@"slider.horizontal.3",@"color":@"blue"},
        @{@"id":@"network",@"title":@"Rede e QE",@"subtitle":@"Requisições, identidade e diagnóstico",@"icon":@"network",@"color":@"teal"},
        @{@"id":@"identity",@"title":@"Identidade e Internal",@"subtitle":@"Employee, Dogfood e menus internos",@"icon":@"person.crop.circle.badge.checkmark",@"color":@"purple"},
        @{@"id":@"appearance",@"title":@"Interface e recursos",@"subtitle":@"Liquid Glass, navegação e Dating",@"icon":@"square.stack.3d.up",@"color":@"pink"},
        @{@"id":@"tools",@"title":@"Ferramentas",@"subtitle":@"Browsers, rastreamento e manutenção",@"icon":@"wrench.and.screwdriver",@"color":@"orange"}
    ];
}
+ (NSArray<NSDictionary *> *)allSections {
    return @[
        Section(@"general",@"Geral",@"As alterações são aplicadas aos controles existentes. Algumas opções indicam quando é necessário reiniciar o aplicativo.",@[
            Switch(@"Ativar FBTweak",@"Controle geral dos recursos da tweak.",FBTKeyMasterEnabled,@"power",NO),
            Switch(@"Abrir com três dedos",@"Toque duas vezes com três dedos para abrir estes ajustes.",FBTKeyOpenThreeFingerDoubleTap,@"hand.tap",NO)]),
        Section(@"mobileconfig",@"Catálogo e valores",@"O catálogo local continua disponível quando os metadados QE não podem ser baixados.",@[
            Navigate(@"Catálogo e valores",@"Buscar configurações, parâmetros e overrides.",@"localconfig",@"list.bullet.rectangle",@"MobileConfig local todos mapas server_value SYS default config param"),
            Navigate(@"Leituras ao vivo",@"Valores e origens observados pelo mecanismo nativo.",@"mobileconfig",@"waveform.path",@"MobileConfig Live runtime uint64 monitor"),
            Action(@"Preparar arquivo de overrides",@"Cria o arquivo no caminho disponibilizado pelo aplicativo.",@"ensure_mc_file",@"doc.badge.plus")]),
        Section(@"mobileconfig",@"Leitura e overrides",@"Uma leitura local pode vir de cache, servidor ou default. Ela não confirma um download novo.",@[
            Switch(@"Leitores MobileConfig",@"Ativa os registros e a leitura pela sessão nativa.",FBTKeyMobileConfigRuntimeEnabled,@"slider.horizontal.3",NO),
            Switch(@"Preparar interface nativa",@"Prepara os contextos e permite uma nova tentativa da seleção.",FBTKeyMobileConfigNativeUIWarmupEnabled,@"arrow.clockwise",NO),
            Switch(@"Registrar leituras",@"Guarda tipo, origem, resultado e contador das leituras.",FBTKeyMobileConfigCaptureEnabled,@"list.bullet.clipboard",NO),
            Switch(@"Aplicar overrides",@"Habilita os overrides existentes da tweak e do mecanismo nativo.",FBTKeyMobileConfigOverridesEnabled,@"switch.2",NO)]),
        Section(@"network",@"Diagnóstico e consultas",@"Os resultados exibidos vêm dos pedidos e callbacks observados. Ativar a captura não garante aceitação pelo servidor.",@[
            Navigate(@"Diagnóstico QE",@"Fetch, contexto, identidade e respostas do servidor.",@"namesdiagnostic",@"waveform.path.ecg",@"Fetch e contexto QE Diagnóstico do download de nomes params configs device_id sessão OAuth"),
            Navigate(@"Opções dos pedidos QE",@"Dez switches para consultas e Force Name Download.",@"qeoptions",@"switch.2",@"Force Name Download Advanced Settings with_universe_params with_current_experiment_group with_only_current_experiment_group with_experiments with_params with_groups with_group_params with_gatekeepers needs_name skip_qe"),
            Navigate(@"Inspetor de rede",@"Examinar e exportar requisições e respostas no iPhone.",@"networkinspector",@"network",@"Network Inspector HTTP request response Tigon"),
            Action(@"Abrir Whitehat",@"Configurações de testes de rede do próprio aplicativo.",@"whitehat",@"checkmark.shield")]),
        Section(@"network",@"Captura desta sessão",@"Os probes são experimentais e exigem a imagem compatível. O painel de diagnóstico também permite armá-los e pausá-los.",@[
            Switch(@"Registrar diagnóstico QE",@"Permite registrar seleções, contexto e resultados.",FBTKeyMobileConfigFetchDiagnosticsEnabled,@"doc.text.magnifyingglass",NO),
            Switch(@"Observar transporte Tigon",@"Registra status e conclusão dos pedidos. Desarma ao reiniciar.",FBTMCNativeProbeTigonKey,@"arrow.up.arrow.down",NO),
            Switch(@"Observar fetch MobileConfig",@"Registra os argumentos e a conclusão do fetcher. Desarma ao reiniciar.",FBTMCNativeProbeFetcherKey,@"point.3.connected.trianglepath.dotted",NO)]),
        Section(@"network",@"Experimentos de diagnóstico",@"Altere uma variável por vez e compare o resultado real antes de tirar conclusões.",@[
            Action(@"Comparar refresh e hash",@"Teste A/B com restauração do estado anterior.",@"qe_ab",@"arrow.left.arrow.right")]),
        Section(@"identity",@"Menus internos",@"Os controles locais não comprovam autorização ou elegibilidade no servidor.",@[
            Action(@"Internal Settings",@"Abrir o menu interno nativo do aplicativo.",@"native",@"gearshape.2"),
            Action(@"React Native Internal Settings",@"Abrir o menu interno React Native.",@"rn_internal",@"square.stack.3d.up")]),
        Section(@"identity",@"Identidade local",@"As opções marcadas com Reiniciar precisam de uma nova abertura completa do aplicativo.",@[
            Switch(@"Employee / Internal",@"Estado local e integração com menus internos. Reiniciar.",FBTKeyEmployeeEnabled,@"person.crop.circle.badge.checkmark",YES),
            Switch(@"Usuário de teste",@"Comportamento local de test user e seletor de identidade. Reiniciar.",FBTKeyTestUserEnabled,@"person.crop.circle.badge.questionmark",YES),
            Switch(@"Dogfood conhecido",@"Controles e ferramentas Dogfood já mapeados.",FBTKeyKnownDogfoodEnabled,@"dog",NO),
            Switch(@"React Native interno",@"Controles de desenvolvimento React Native. Reiniciar.",FBTKeyReactNativeInternalEnabled,@"square.stack.3d.up",YES),
            Switch(@"Comportamento de sistema beta",@"Predicado local de build beta. Reiniciar.",FBTKeyBetaBuildEnabled,@"testtube.2",YES)]),
        Section(@"identity",@"Instrumentação avançada",@"Esses testes têm alcance maior. Habilite apenas o que deseja investigar.",@[
            Switch(@"Varredura Dogfood",@"Instala os controles BOOL Dogfood descobertos em runtime.",FBTKeyDogfoodSweepEnabled,@"magnifyingglass",NO),
            Switch(@"Varredura Internal e Debug",@"Instala os controles BOOL de menus internos e desenvolvimento.",FBTKeyInternalDebugSweepEnabled,@"ant",NO),
            Switch(@"Import de Internal Settings",@"Controle local do import de disponibilidade do menu.",FBTKeyInternalCImportsEnabled,@"square.and.arrow.down",NO),
            Switch(@"Import de EasyGating",@"Teste amplo do import de gates internos. Use isoladamente.",FBTKeyEasyGatingInternalEnabled,@"line.3.horizontal.decrease",NO)]),
        Section(@"appearance",@"Apresentação",@"O visual destes ajustes é independente dos controles que modificam a interface do Facebook.",@[
            Switch(@"Liquid Glass no Facebook",@"Ativa os controles conhecidos de Liquid Glass. Reiniciar.",FBTKeyLiquidGlassEnabled,@"sparkles",YES),
            Navigate(@"Parâmetros de Liquid Glass",@"Examinar parâmetros e overrides relacionados.",@"feat:LiquidGlass",@"slider.horizontal.3",@"Liquid Glass params"),
            Switch(@"Barra de abas flutuante",@"Ativa os controles conhecidos da barra. Reiniciar.",FBTKeyFloatingTabBarEnabled,@"rectangle.bottomthird.inset.filled",YES),
            Navigate(@"Parâmetros da barra de abas",@"Examinar parâmetros de navegação flutuante.",@"feat:FloatingTab",@"slider.horizontal.3",@"Floating Tab Bar params")]),
        Section(@"appearance",@"Recursos",@"A disponibilidade final também depende da conta e do servidor.",@[
            Switch(@"Dating / Gemstone",@"Controles locais do recurso. Reiniciar.",FBTKeyDatingEnabled,@"heart",YES),
            Navigate(@"Parâmetros de Dating",@"Gates e overrides relacionados ao recurso.",@"feat:DatingGemstone",@"heart.text.square",@"Dating Gemstone gates")]),
        Section(@"tools",@"Inspeção ao vivo",@"Os browsers podem observar valores e aplicar overrides conforme seus controles.",@[
            Navigate(@"Runtime Browser",@"Classes, métodos, símbolos e dados dos frameworks.",@"bool",@"curlybraces",@"ObjC C DATA Swift symbols runtime"),
            Navigate(@"BOOL ao vivo",@"Observar retornos e revisar overrides BOOL.",@"boollive",@"switch.2",@"ObjC BOOL Live"),
            Navigate(@"Rastreamento nativo",@"Eventos em memória e exportação de diagnóstico.",@"livetrace",@"waveform.path.ecg",@"Native Live Trace"),
            Switch(@"Habilitar browser BOOL",@"Permite busca e restauração dos hooks BOOL persistidos.",FBTKeyRuntimeBoolBrowserEnabled,@"curlybraces",NO)]),
        Section(@"tools",@"Referências locais",@"Os catálogos empacotados não comprovam que um recurso foi ativado.",@[
            Navigate(@"Flags em destaque",@"Internal, Dogfood, Dating e Debug.",@"headline",@"flag",@"Headline flags"),
            Navigate(@"Catálogo completo de flags",@"Consultar o mapa empacotado com a tweak.",@"flags",@"list.bullet.rectangle",@"Dump completo flags"),
            Navigate(@"Configurações de consultas",@"Referências GraphQL empacotadas.",@"queries",@"doc.text",@"Query configs enviados GraphQL")]),
        Section(@"tools",@"Manutenção",@"A remoção solicita confirmação e preserva o comportamento existente dos hooks.",@[
            Action(@"Limpar overrides da tweak",@"Remove os overrides MobileConfig e BOOL persistidos.",@"clear",@"trash")])
    ];
}
+ (NSArray<NSDictionary *> *)sectionsForCategory:(NSString *)category query:(NSString *)query {
    NSString *q=[Fold(query) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *all=[self allSections];
    if (!category.length && !q.length) {
        NSMutableArray *areas=[NSMutableArray array];
        for(NSDictionary *c in [self categories]) {
            NSMutableDictionary *row=[Navigate(c[@"title"],c[@"subtitle"],[@"category:" stringByAppendingString:c[@"id"]],c[@"icon"],@"") mutableCopy];
            row[@"color"]=c[@"color"]; [areas addObject:row];
        }
        NSArray *quick=@[Navigate(@"Diagnóstico QE",@"Fetch, identidade e respostas.",@"namesdiagnostic",@"waveform.path.ecg",@""),
            Navigate(@"Opções dos pedidos QE",@"Editar os dez campos da consulta.",@"qeoptions",@"switch.2",@""),
            Navigate(@"Inspetor de rede",@"Requisições e respostas no iPhone.",@"networkinspector",@"network",@"")];
        return @[all.firstObject,Section(@"home",@"Acesso rápido",@"",quick),Section(@"home",@"Explorar por área",@"",areas)];
    }
    NSMutableArray *sections=[NSMutableArray array];
    for(NSDictionary *s in all) {
        if(category.length && ![s[@"category"] isEqual:category]) continue;
        NSMutableArray *rows=[NSMutableArray array];
        for(NSDictionary *r in s[@"rows"]) {
            NSString *haystack=Fold([@[r[@"title"]?:@"",r[@"subtitle"]?:@"",r[@"keywords"]?:@"",r[@"dest"]?:@"",r[@"action"]?:@"",r[@"key"]?:@"",s[@"title"]?:@""] componentsJoinedByString:@" "]);
            BOOL matches=YES;
            for(NSString *token in [q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
                if(token.length && [haystack rangeOfString:token].location==NSNotFound) { matches=NO; break; }
            if(matches) [rows addObject:r];
        }
        if(rows.count) { NSMutableDictionary *copy=[s mutableCopy];copy[@"rows"]=rows;[sections addObject:copy]; }
    }
    return sections;
}
@end
