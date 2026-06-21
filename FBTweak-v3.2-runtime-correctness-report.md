# FBTweak v3.2 — runtime correto sem patch em `__TEXT`

## Diagnóstico real

O v3 caiu por `CODESIGNING / Invalid Page` ao executar `MSGCSessionedMobileConfigGetString+796` dentro de `FBSharedFramework`. Isso prova que `MSHookFunction` em função C exportada do framework assinado sujou página `__TEXT` e o kernel matou o app. Portanto a correção correta não é trocar por outro inline hook: é não fazer inline patch em código assinado nesse ambiente.

## Correção arquitetural

### MobileConfig

- Mantido fishhook nos imports/GOT dos readers `MSGCSessionedMobileConfigGetBoolean/Int64/Double/String` para capturar chamadas que cruzam images.
- Adicionada camada `FBTNativeMobileConfigOverrides.mm`.
- Essa camada captura `FBMobileConfigContext` por hooks ObjC seguros em getters de contexto de classes `FBMobileConfig*`/`IGMobileConfig*`.
- Ao aplicar override, tenta primeiro o caminho nativo:
  - `getMobileConfigManager(context)`
  - `FBMobileConfigManager::getOrCreateOverridesTable(true)`
  - `FBMobileConfigOverridesTable::updateOverrideForParam(...)`
  - `removeOverrideForParam(...)`
- Se ainda não houver contexto vivo, o override continua persistido no fallback fishhook por chave capturada.
- Nenhuma função C exportada do `FBSharedFramework` é patchada via `MSHookFunction`.

### Runtime BOOL Browser

Corrigido o bug do filtro. Antes o browser calculava `dladdr` só depois do filtro por classe/selector; por isso buscar `FBSharedFramework`, `main-exec` ou `Frameworks` não retornava direito. Agora o filtro inclui:

- classe
- selector
- `imageKind`
- path real do image via `dladdr(method_getImplementation(...))`

Isso torna o browser realmente pesquisável por executable principal, FBSharedFramework e frameworks carregados.

### Query configs

Atualizado o bundle `FBTweak.bundle/QueryConfigs` com os JSONs enviados neste turno, incluindo `AdsLWIBoostedPostManagementQueryConfigs.json`, `FBGamingTabHomeSurfaceQueryConfigs.json` e `FBRelayComputedVariablesConfig.json`.

## Limite honesto

Chamadas C internas do mesmo image não são capturadas por fishhook. Em vez de voltar ao `MSHookFunction` perigoso, v3.2 usa a tabela nativa de overrides. O efeito correto para MobileConfig interno vem por `FBMobileConfigOverridesTable`, não por patchar a instrução do reader.
