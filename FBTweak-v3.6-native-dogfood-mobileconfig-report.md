# FBTweak v3.6 — Native Dogfood MobileConfig path

## Motivo

O menu nativo Dogfood mostrou que o fluxo de overrides não depende de rede interna para aplicar valores. A rede interna é exigida apenas pelo fluxo de nomes (`Force name download`). O storage nativo é:

```text
<AppGroup>/group.com.facebook.dogfood.internal/mobileconfig/mc_overrides.json
```

A correção v3.6 não volta para `MSHookFunction` em símbolos C de `FBSharedFramework`, porque o crash real anterior provou `CODESIGNING / Invalid Page`. A solução passa por dispatch ObjC e APIs nativas já existentes.

## Achados validados no binário

### Facebook executable

Classe:

```text
FBMobileConfigFBTContextManager
```

Ivars:

```text
_fbtHashToMCSpecifierMapping NSDictionary
_mobileconfig <FBMobileConfigDebugAPI>
```

Métodos:

```text
initWithFbtToMCIdMapping:mobileconfig:
mobileconfig
getMCSpecifier:
getConfigValue:
getConfigValue:withOptions:
```

Esse é o bridge que entrega o objeto `<FBMobileConfigDebugAPI>` usado pelo menu nativo.

### FBSharedFramework

Classes/métodos relevantes:

```text
FBMobileConfigStartupConfigs
  getBool:withOptions:withDefault:
  getInt64:withOptions:withDefault:
  getDouble:withOptions:withDefault:
  getString:withOptions:withDefault:
  setOverrideForParam:andValue:       v32@0:8Q16@24
  removeOverrideForParam:             v24@0:8Q16

FBMobileConfigUserSessionContextManager
  getBool:withOptions:
  getInt64:withOptions:
  getDouble:withOptions:
  getString:withOptions:

FBMobileConfigSessionlessContextManager
  getBool:withOptions:
  getInt64:withOptions:
  getDouble:withOptions:
  getString:withOptions:

FBMobileConfigContextObjcImpl
FBMobileConfigContextManager
IGMobileConfigContextManager
IGMobileConfigUserSessionContextManager
IGMobileConfigSessionlessContextManager
  readers tipados equivalentes

FBMobileConfigContextManager / IGMobileConfigContextManager / FBMobileConfigEmptyImpl
  getOverridesTablePath
```

Exports C++ continuam presentes:

```text
getMobileConfigManager(FBMobileConfigContext)
FBMobileConfigManager::getOrCreateOverridesTable(bool)
FBMobileConfigOverridesTable::updateOverrideForParam(...)
FBMobileConfigOverridesTable::removeOverrideForParam(...)
```

## Implementação v3.6

### 1. Hook ObjC dos readers nativos

`FBTNativeMobileConfigOverrides.mm` agora instala `MSHookMessageEx` nos readers ObjC conhecidos. Isso pega chamadas do framework sem patch direto em `__TEXT`:

```text
getBool:withOptions:
getBool:withOptions:withDefault:
getInt64:withOptions:
getInt64:withOptions:withDefault:
getDouble:withOptions:
getDouble:withOptions:withDefault:
getString:withOptions:
getString:withOptions:withDefault:
```

Cada hook:

1. chama o original;
2. registra a key viva no MobileConfig Live;
3. consulta override persistido por key;
4. retorna o valor forçado quando existe override do mesmo tipo.

### 2. Captura do objeto nativo `<FBMobileConfigDebugAPI>`

Hook novo em:

```text
FBMobileConfigFBTContextManager initWithFbtToMCIdMapping:mobileconfig:
FBMobileConfigFBTContextManager mobileconfig
```

Ele registra o objeto que responde a:

```text
setOverrideForParam:andValue:
removeOverrideForParam:
getOverridesTablePath
```

### 3. Aplicação nativa de override

`FBTNativeMobileConfigApplyOverride()` agora tenta, nesta ordem:

1. Objeto ObjC nativo `<FBMobileConfigDebugAPI>` / `FBMobileConfigStartupConfigs` via `objc_msgSend`;
2. C++ `FBMobileConfigOverridesTable` via contexto vivo;
3. fallback já existente no accessor fishhook/ObjC runtime.

O hook só chama `setOverrideForParam:andValue:` quando a assinatura usa key escalar (`Q16` ou `{mc_...=Q}`), evitando chamar variantes antigas que recebem objeto.

### 4. Arquivo nativo de overrides

Foi adicionado:

```text
FBTNativeMobileConfigOverridesFilePath()
FBTNativeMobileConfigEnsureOverridesFile()
```

O path vem primeiro de `getOverridesTablePath`. Se ainda não houver objeto nativo capturado, cai para `containerURLForSecurityApplicationGroupIdentifier("group.com.facebook.dogfood.internal")` e monta:

```text
mobileconfig/mc_overrides.json
```

A UI ganhou a ação:

```text
Criar mc_overrides.json nativo
```

### 5. Buildfix extra

`FBTFlagCatalog.m` não usa mais `NSNumber.unsignedLongLongValue`; agora usa `strtoull([[n stringValue] UTF8String], ...)`, compatível com o SDK/Theos atual.

## O que não foi feito

Não reintroduzi `MSHookFunction` em export C de `FBSharedFramework`. Esse caminho já foi provado inválido pelo crash de codesigning.

Não tento baixar nomes via `Force name download`, porque o próprio erro do menu mostra dependência de rede/grupo interno. A tweak precisa aplicar por key viva capturada, não depender do resolvedor de nomes.
