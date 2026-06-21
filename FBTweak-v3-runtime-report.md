# FBTweak v3 — runtime real no framework + executable

Correções principais:

- v3 tentou `dlsym + MSHookFunction` direto nos exports `MSGCSessionedMobileConfigGetBoolean/Int64/Double/String`; v3.1 removeu isso porque o crash real mostrou `CODESIGNING / Invalid Page` em `FBSharedFramework` ao executar página `__TEXT` suja.
- Runtime BOOL browser agora mostra origem do método (`main-exec`, `FBSharedFramework`, `framework`, `system`) usando `dladdr(method_getImplementation(...))`, então a busca pode filtrar explicitamente por `FBShared` ou `main-exec`.
- Liquid Glass não depende mais só de `_METAIsLiquidGlassEnabled` (que pode nem existir nesse build). Ele tenta fishhook/dlsym para o símbolo C quando existir, hooks diretos em helpers Swift conhecidos de LiquidGlass e instala overrides no Runtime BOOL Browser para getters LiquidGlass carregados.
- Togglar MobileConfig runtime, Runtime BOOL e Liquid Glass pelo painel agora tenta instalar imediatamente; ainda assim, hooks Logos de Employee/Floating/Dating continuam mais seguros com restart.

O v2 falhava porque fishhook sozinho não intercepta chamadas internas do mesmo framework e porque o símbolo `METAIsLiquidGlassEnabled` não aparece no `FBSharedFramework` analisado; só abrir Internal Settings funcionava porque era chamada direta para a fábrica nativa.


## v3.1 crashfix

Crash real analisado: `CODESIGNING / Invalid Page` em `FBSharedFramework` dentro de `MSGCSessionedMobileConfigGetString+796`, PC `0x10f68e08c`, image offset `0x166a08c`. Causa: `MSHookFunction` direto em símbolo C do FBSharedFramework sujou página `__TEXT` assinada (`rw-/rw-`, sem execute). Correção: remover direct C hooks por `dlsym+MSHookFunction` em MobileConfig/LiquidGlass/Dating e manter apenas fishhook para imports + MSHookMessageEx para ObjC selectors do runtime browser.
