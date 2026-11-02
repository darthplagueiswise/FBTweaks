# Instagram iOS 453 — auditoria Capstone / XPlugins / MobileConfig
## Execução verificada em 2026-11-02
**Fonte primária histórica:** `FBSharedFramework(4)`, SHA256 `b87afc433805d3579d1e606b36254ad67228a5c873d10601f2c756ca843fe45f`, LC_UUID `4c4c446455553144a1031e54865a1439`.
Os arquivos mais recentes da Biblioteca (`Instagram(3)`, `Instagram(2).ipa`, `FBSharedFramework(5)`) foram identificados, mas a materialização binária foi recusada, impedindo comparar bytes e revalidar o UUID. Não atribuir automaticamente a versão 453 a essas três cópias.

**Ferramenta executada:** GitHub Actions run https://github.com/darthplagueiswise/FBTweaks/actions/runs/41488881399. Capstone Python importado (módulo reporta 5.0.7; pip instalou distribuição capstone-5.0.9). Os 11 *opcodes BL de quatro bytes* extraídos em investigação anterior foram remontados em little-endian, decodificados como ARM64 e testados: 11/11 destinos corretos. O código-fonte e o artefato JSON estão nesse run. Nenhum Mach-O completo foi enviado ao runner ou nele decompilado.

## Grafo de chamada parcialmente confirmado
| Caller RVA | ARM64 | Callee RVA | Significado comprovado |
|---|---|---|---|
| 0x97A64 | BL | 0x97A18 | Chamada `XPluginsGetDataForSocket` |
| 0x9BE28 | BL | 0x97A18 | Chamada `XPluginsGetDataForSocket` |
| 0x186CF24 | BL | 0x9E868 | Chamada `XPluginsGetFunctionPtrFromID` |
| 0x187A6B0 | BL | 0x9E868 | Chamada `XPluginsGetFunctionPtrFromID` |
| 0x172E034 | BL | 0xC5B02C | `IGDogfoodingAssistantLauncherClient.clearAllOverrides` |
| 0x117EA88 | BL | 0x11311C0 | `IGDogfoodingAssistantLauncherClient.currentParamValue` |
| 0x123F4C8 | BL | 0x1827E24 | `IGMobileConfigForceUpdateConfigs` |
| 0x123F538 | BL | 0x1827E24 | `IGMobileConfigForceUpdateConfigs` |
| 0x8C5020 | BL | 0x8C5610 | `FBMobileConfigStorageManager.persistConfigsFromDeltaResponse` |
| 0x2F5954 | BL | 0x12EB8C | `FBMobileConfigManager.getOrCreateOverridesTable` |
| 0xDB2C6C | BL | 0x12EB8C | `FBMobileConfigManager.getOrCreateOverridesTable` |

Os XREFs anteriores contêm 227 BL diretos para DataForSocket e 35 para FunctionPtrFromID. A verificação Capstone recém-executada contemplou **somente 4 exemplos** desse subconjunto e 7 calls de outros subsistemas, não o conjunto completo de 262 XREFs nem os `BLR`.

## 1. Predicados Dogfooding — PARCIAL
Exports Swift confirmados: `clearAllOverrides(userSession:)` 0xC5B02C, `currentParamValue(userSession:launcherName:paramName:)` 0x11311C0 e `sessionBrowserViewController(userSession:)` 0x1131230. No executável, metadata Swift `DogfoodingFirstCoordinator` registra campos store, environment, user, dogfooder, mobileConfig, logger e strictModeConfig; `IGDogfoodingSettingsViewController` registra userSession e itemOverrides. Há também o construtor ObjC `IGDogfooderProd.initWithLauncherSet:networker:logger:` RVA 0x1055EA59C. Esses dados mostram dependências estruturais e funções reais, mas **não** reconstruíram o predicado de apresentação, a decisão remota ou o fluxo de registro de launcher.

## 2. Registro e despacho XPlugins — PARCIAL
No Shared, `XPluginsGetDataForSocket` 0x97A18 resolve dinamicamente a string `XPluginsGetDataPair` e executa `BR X1` quando encontra a implementação. `XPluginsGetFunctionPtrFromID` 0x9E868 resolve `XPluginsGetFuncPtr` e encaminha por `BR X2`. No executável, exports de registro/lookup estão em `XPluginsGetDataPair` 0x105472E40 e `XPluginsGetFuncPtr` 0x10546E208. **Ainda não existe** a tabela verificada socket ID → function ID → provider → handler → controller; a varredura BL prévia não cobre dispatch indireto.

## 3. Employee e Test User — PARCIAL
Schema empacotado contém `IGUserIsEmployeeOrTestUserFragmentImpl` e `IGInternalSettingsAvailabilityFragmentImpl`; há strings `is_internal`/`is_employee`. Não há XREF recuperado ligando o fragmento aos getters, à sessão e ao predicado do launcher, e o nome do fragmento não prova o comportamento/autoridade do backend. Categoria contractor/trainer humano não encontrada no recorte anterior (ocorrências `Trainer` pareciam denominar componentes de ML).

## 4. Serialização HTTP e callbacks — DESCONHECIDO
`IGMobileConfigInitParams` recebe argumentos distintos `deviceId`, `familyDeviceId`, `unitType`, `containerPath` e sessão; não há prova dos bytes HTTP finais, seleção de host, headers, payload de resposta, `query_hash`, URL real nem resultado em execução para a versão IG. Rotas `/launcher/mobileconfigqeinfo/` são de ferramentas internas e não são prova de endpoint de rede. OAuth #100 foi observado no projeto Facebook, não atribuído ao Instagram nesta captura.

## 5. Respostas e persistência — PARCIAL
Export da persistência delta 0x8C5610 e caller direto 0x8C5020 verificados. Também há símbolos `FBMobileConfigManager.updateConfigsWithParamsListSynchronously` 0x15D23D0, `FBMobileConfigIdNameMap.getIdToNameFilePath` 0x14D08C, `IGMobileConfigForceUpdateConfigs` 0x1827E24. Os pares de callback, sucesso de parsing, gravação .mctable e atualização de contextos não foram recuperados com o material executável desta sessão.

## 6. Overrides e valor efetivo — PARCIAL
Metadata ObjC confirma:
- `FBMobileConfigManager.getOrCreateOverridesTable` 0x12EB8C, com BL diretos em 0x2F5954 e 0xDB2C6C.
- `IGMobileConfigContextManager.getBool:` 0x2F5CA8; `getBool:withOptions:` 0x30EAC4; `latestContextForConfig:` 0x2F58B0.
- `FBMobileConfigOptions.setIgnoreOverrideForInternalUse` 0x941F50; `setFromRN` 0x12E8C8; `setFromInternalRequest` 0x12C108; `valueSource` 0x12F928.
- `FBMobileConfigStartupConfigs.isOverrideValue:` 0x1715C20, `setOverrideForParam:andValue:` 0x1715570, `configValuesOverride` 0xB5B48.
A proximidade da chamada 0x2F5954 com `latestContextForConfig:` em 0x2F58B0 é uma pista, **não prova ainda** a delimitação do método ou a sequência de precedência. A capacidade de ignorar overrides indica política condicional, mas **não** qual flag vence no getter, nem se override salvo é lido em runtime.

## Bloqueios efetivos desta execução
1. O executor local (container e Python) falha antes de iniciar qualquer processo. Não foi possível ler o Mach-O completo com Capstone local.
2. A Biblioteca disponibiliza as três cópias recentes, mas `files.materialize` recusou exportação de raw bytes para o `FBSharedFramework(5)`. Não enviaremos esses Mach-O privados a um repositório público.
3. Sem o corpo das funções não é correto afirmar predicados, registry completo, serialização final, autenticação nem precedência efetiva.
4. O relatório mantém os endereços do **FBSharedFramework(4) historicamente analisado**; validação cruzada contra (5) continua não executada.

**Classificação geral:** 11 BL Capstone CONFIRMADOS; existência dos tipos/métodos ObjC/Swift CONFIRMADA historicamente; Dogfooding/XPlugins/overrides PARCIAIS; Employee e HTTP final NÃO CONCLUÍDOS.
