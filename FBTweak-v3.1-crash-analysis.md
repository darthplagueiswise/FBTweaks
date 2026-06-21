# FBTweak v3.1 — crashfix real

## Crash analisado

Arquivo: `Facebook-2026-06-21-150043.ips`

- Processo: Facebook 566.1.0 (`com.facebook.dogfood.internal`)
- Launch: 2026-06-21 15:00:41.8881 -0300
- Crash: 2026-06-21 15:00:42.3455 -0300
- Exception: `EXC_BAD_ACCESS / SIGKILL`
- Termination: `CODESIGNING`, indicator `Invalid Page`
- Ktriage: `Failed to fault in a page with execute permissions`
- Faulting thread: main thread
- Faulting symbol: `MSGCSessionedMobileConfigGetString + 796`
- Faulting image: `FBSharedFramework`
- Faulting PC: `0x10f68e08c`
- FBShared image base: `0x10e024000`
- Image offset: `0x166a08c`

## Causa

v3 instalava `MSHookFunction` direto nos exports C do `FBSharedFramework`:

- `MSGCSessionedMobileConfigGetBoolean`
- `MSGCSessionedMobileConfigGetInt64`
- `MSGCSessionedMobileConfigGetDouble`
- `MSGCSessionedMobileConfigGetString`

Esse patch direto sujou página `__TEXT` assinada. O crash mostra exatamente a página alterada como `rw-/rw-`, sem permissão de execute, e o kernel matou o app por code signing ao tentar executar `MSGCSessionedMobileConfigGetString+796`.

## Correção

- Removido direct C hook por `dlsym + MSHookFunction` em MobileConfig.
- MobileConfig volta para `fishhook` only nos imports/GOT.
- Removido direct C hook por `MSHookFunction` em LiquidGlass e Dating.
- Runtime BOOL Browser continua com `MSHookMessageEx` para selectors ObjC carregados, incluindo classes do executable principal e `FBSharedFramework`; isso não patcha página `__TEXT` C do framework.

## Limite honesto

fishhook não captura chamadas internas do mesmo image. Então MobileConfig C interno do próprio `FBSharedFramework` não deve ser patchado por direct C hook nesse ambiente sideload/iOS, porque o crash real provou que isso vira `CODESIGNING / Invalid Page`. O caminho seguro para framework + exec principal é ObjC runtime browser via `MSHookMessageEx` para getters ObjC/Swift-dispatch hookáveis.
