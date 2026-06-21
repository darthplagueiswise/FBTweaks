# FBTweak v3.4 — SDK 26 buildfix

## Motivo

O build v3.3 falhou no CI por incompatibilidades de headers/SDK:

- `NSString` não expõe `unsignedLongLongValue` nos headers usados pelo Theos/SDK 26.2.
- `CFBridgingRetain` retorna `CFTypeRef`, e atribuir direto em campo `CFStringRef` falha em Objective-C++.

## Correções

### `src/Runtime/FBTMobileConfigRuntime.m`

- Adicionado `#include <stdlib.h>`.
- Criado helper C local:
  - `FBTMCParseUInt64String(NSString *)`
- Substituído:
  - `[ks unsignedLongLongValue]`
- Por:
  - `FBTMCParseUInt64String(ks)`

### `src/Settings/FBTSettingsViewController.m`

- Adicionado `#include <stdlib.h>`.
- Criados helpers C locais:
  - `FBTParseUInt64String(NSString *)`
  - `FBTParseLongLongString(NSString *)`
- Substituído parse de key MobileConfig por `strtoull`.
- Substituído parse de int64 manual por `strtoll`.

### `src/Runtime/FBTNativeMobileConfigOverrides.mm`

- Corrigido cast explícito:
  - `desc->key = (CFStringRef)CFBridgingRetain(key);`

### `src/Runtime/FBTRuntimeBoolBrowser.m`

- Aplicado o mesmo cast explícito no descriptor do runtime BOOL browser para evitar erro igual quando esse arquivo for compilado.

## Escopo

Não muda a arquitetura de hooks. Continua sem `MSHookFunction` em `__TEXT` assinado do `FBSharedFramework`.

Mantém:

- fishhook para imports/GOT.
- runtime ObjC BOOL browser via `MSHookMessageEx`.
- native MobileConfig override table quando contexto vivo for capturado.
