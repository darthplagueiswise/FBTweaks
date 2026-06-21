# FBTweak v2 — UIKit + Runtime MobileConfig

## Base

Parti do `FBTweak-flags.zip` e removi a camada SwiftUI. A UI agora é UIKit puro em `src/Settings/FBTSettingsViewController.m`.

## Símbolos validados no FBSharedFramework enviado

`llvm-objdump --macho --exports-trie /mnt/data/FBSharedFramework` confirmou:

```text
_MSMS/MSG readers tipados:
MSGCSessionedMobileConfigGetBoolean
MSGCSessionedMobileConfigGetInt64
MSGCSessionedMobileConfigGetDouble
MSGCSessionedMobileConfigGetString

MobileConfig manager/override symbols presentes:
getMobileConfigManager(FBMobileConfigContext*)
mobileconfig::FBMobileConfigManager::getOrCreateOverridesTable(bool)
mobileconfig::FBMobileConfigOverridesTable::updateOverrideForParam(uint64_t, bool/double/int64/string, bool)
mobileconfig::FBMobileConfigOverridesTable::removeOverrideForParam(uint64_t, bool)

Outros gates já existentes no pacote:
GemstoneMsysEnabled
GemstoneMsysThreadViewEnabled
GemstoneMsysThreadListEnabled
GemstoneMsysInactivatedThreadListEnabled
MEBIsMinosDogfoodMekEncryptionVersionEnabled
```

## Implementado

### MobileConfig Live

Arquivo: `src/Runtime/FBTMobileConfigRuntime.m`

- Instala fishhook nos imports `MSGCSessionedMobileConfigGetBoolean`, `GetInt64`, `GetDouble`, `GetString`.
- ABI usada: `x0=context/descriptor`, `x1=uint64 key`, `x2=default`, `x3=extra`.
- Captura key viva em runtime. Não tenta construir a packed key offline a partir do JSON.
- Salva override por key decimal em `fbt_mobileconfig_overrides`.
- Aplica override no accessor fishhookado, antes de devolver valor ao caller.
- Tipos suportados: bool, int64, double, string.
- Hot path não chama `NSUserDefaults`; usa cache estático recarregado por `FBTNotificationPrefsChanged`.

### ObjC BOOL Runtime Browser

Arquivo: `src/Runtime/FBTRuntimeBoolBrowser.m`

- Varredura de classes acontece só na tela do browser / ação Buscar.
- Indexa methods BOOL/char sem argumentos, de instância e metaclass.
- Key persistida: `Classe#selector` ou `+Classe#selector`.
- Instala hook com `MSHookMessageEx + imp_implementationWithBlock`.
- Persistidos são reinstalados no `%ctor` sem varrer runtime.
- UI permite Force ON, Force OFF e Clear.

### UIKit / Liquid Glass default

Arquivo: `src/Settings/FBTSettingsViewController.m`

- `UITableViewStyleInsetGrouped`.
- `UISearchController` nos browsers.
- `UINavigationBarAppearance configureWithDefaultBackground`.
- Sem Swift, sem UIHostingController, sem NavigationStack.
- Sem customização de blur, cor, posição ou animação de sheet.

### QueryConfigs

Os JSONs enviados foram empacotados em:

```text
layout/Library/Application Support/FBTweak.bundle/QueryConfigs/
```

A UI inclui browser básico para nome, id, arquivo e variáveis.

## Validação local executada

- `scripts/validate-sdk26.sh` executado com SDK fake para validar grep/estrutura.
- Confirmado: sem `.swift` em `src/`.
- Confirmado: `MSGCSessionedMobileConfigGetBoolean` no runtime.
- Confirmado: `MSHookMessageEx` no runtime bool browser.
- Confirmado: `configureWithDefaultBackground` na UI.

## Observação honesta

O caminho de override nativo `FBMobileConfigOverridesTable` existe no binário, mas exige ABI C++/`shared_ptr` com contexto vivo e é mais frágil do que o accessor hook. Esta versão resolve o problema prático da forma certa para tweak: captura a key real no reader e aplica override tipado no reader. Isso evita inventar packed key offline e evita mexer no storage C++ interno.
