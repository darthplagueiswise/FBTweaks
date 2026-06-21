# FBTweak v3.3 — buildfix for `-Wunused-variable`

Correção estrita em cima do v3.2.

## Causa do erro

Depois da remoção dos hooks C diretos em `FBSharedFramework` para evitar `CODESIGNING / Invalid Page`, sobraram ponteiros `orig_*` declarados em:

- `src/Features/Dating/FBTDating.m`
- `src/Features/LiquidGlass/FBTLiquidGlass.m`

Como o build usa `-Werror`, essas variáveis estáticas não usadas viraram erro fatal.

## Correção aplicada

- Removidos os restos de direct C hook de Dating.
- Removidos os ponteiros `orig_IGLiquidGlassNavigationExperiment_isEnabled` e `orig_IGThrowbackChromeExperiment_isEnabled`.
- Mantido o caminho seguro:
  - `fishhook` para `METAIsLiquidGlassEnabled` quando importado;
  - `Runtime BOOL Browser` para selectors ObjC/Swift;
  - MobileConfig fishhook + native override table.

Não foi reintroduzido `MSHookFunction` em símbolo C de `FBSharedFramework`.
