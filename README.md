# FBTweak

Tweak Theos/rootless para o Facebook iOS, arm64, SDK iPhoneOS 26.2 / min iOS 16.3. Abertura por long-press na tab bar.

## v3.2 — runtime correto

- MobileConfig: fishhook nos imports + OverridesTable nativo via contextos ObjC capturados.
- Sem `MSHookFunction` em símbolos C do `FBSharedFramework` assinado.
- Runtime BOOL Browser agora busca por `main-exec`, `FBSharedFramework`, `framework` e path real do image.
- QueryConfigs atualizados no bundle.


## O que esta versão entrega

- **UI UIKit pura**, sem Swift, sem bridging header, sem modulemap. O painel usa `UITableViewStyleInsetGrouped`, `UISearchController`, `UINavigationController` e `UINavigationBarAppearance configureWithDefaultBackground`, deixando o iOS aplicar o Liquid Glass/default background nativo.
- **Hooks conhecidos no padrão Ryukgram**:
  - Employee/Internal por Logos em getters ObjC conhecidos + `MSHookMessageEx` para classe Swift conhecida.
  - Floating Tab Bar por Logos em getters conhecidos.
  - Liquid Glass por fishhook em `METAIsLiquidGlassEnabled`.
  - Dating/Gemstone: sem direct C hook em __TEXT assinado; use Employee/Internal + Runtime BOOL Browser para gates ObjC hookáveis.
  - Internal Settings nativo por ação manual: `FBInternalSettingsViewControllerFromSession(session)`.
- **MobileConfig Live**:
  - fishhook nos readers importados `MSGCSessionedMobileConfigGetBoolean`, `GetInt64`, `GetDouble`, `GetString`;
  - captura a chave `uint64` real que o app leu em runtime, tipo, default, resultado, contador e timestamp;
  - aplica override manual por chave capturada, sem tentar construir chave offline a partir do JSON;
  - overrides persistem em `NSUserDefaults` e entram em backup/export porque a key está nos defaults registrados.
- **ObjC BOOL Runtime Browser hookável**:
  - varredura de classes/selectors só quando a tela abre ou quando o usuário toca em Buscar;
  - lista getters BOOL sem argumentos de instância e classe;
  - salva Force ON / Force OFF / Clear;
  - reinstala hooks persistidos no `%ctor` com `MSHookMessageEx + imp_implementationWithBlock`;
  - o replacement não lê `NSUserDefaults` na hot path, usa cache estático recarregado por notificação.
- **Browsers auxiliares**:
  - Headline flags;
  - Dump completo `FBTFlags.json`;
  - QueryConfigs enviados, empacotados em `FBTweak.bundle/QueryConfigs/`.

## Timing correto

O `%ctor` faz apenas leituras baratas de pref e instala:

1. host do long-press;
2. observer barato para abrir Internal Settings nativo;
3. hooks conhecidos ligados no launch;
4. runtime bool persistido, sem varrer classes;
5. MobileConfig runtime, se a pref já estava ON;
6. Liquid Glass fishhook, se a pref já estava ON.

Ligar hooks conhecidos ou MobileConfig runtime pela primeira vez pode exigir reabrir o Facebook. Depois que o hook já está instalado, captura/overrides e alguns toggles mudam ao vivo.

## Build

```sh
export THEOS=~/theos
./build.sh rootless
```

O CI usa `iPhoneOS26.2.sdk`, rootless, arm64, `FINALPACKAGE=1`.

## v3.3 buildfix

Correção de build: remove restos `orig_*` não usados de Dating/LiquidGlass que quebravam CI com `-Werror,-Wunused-variable`. Não reintroduz hook C direto em `__TEXT` assinado.
