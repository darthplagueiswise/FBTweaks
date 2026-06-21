# FBTweak v3.5 — ObjC++ linkage buildfix

## Erro corrigido

O build falhava no link com símbolos C usados por arquivos `.m`:

- `_FBTInstallNativeMobileConfigContextCapture`
- `_FBTNativeMobileConfigApplyOverride`
- `_FBTNativeMobileConfigRemoveOverride`
- `_FBTNativeMobileConfigStatus`

Essas funções são implementadas em `src/Runtime/FBTNativeMobileConfigOverrides.mm`. Como `.mm` compila como Objective-C++, as definições estavam sendo emitidas com C++ name mangling, enquanto os callers Objective-C esperavam símbolos C simples com prefixo `_FBT...`.

## Fix aplicado

Arquivo alterado:

```text
src/Runtime/FBTNativeMobileConfigOverrides.h
```

Foi adicionado `extern "C"` nos protótipos públicos quando compilado sob C++/Objective-C++:

```objc
#ifdef __cplusplus
extern "C" {
#endif

void FBTInstallNativeMobileConfigContextCapture(void);
void FBTNativeMobileConfigRegisterContext(id context);
NSUInteger FBTNativeMobileConfigContextCount(void);
NSString *FBTNativeMobileConfigStatus(void);
BOOL FBTNativeMobileConfigApplyOverride(uint64_t key, NSString *type, id value);
BOOL FBTNativeMobileConfigRemoveOverride(uint64_t key);

#ifdef __cplusplus
}
#endif
```

Como a `.mm` importa esse header antes das definições, as definições passam a manter C linkage e o linker resolve os callers Objective-C.

## Escopo

Não muda a estratégia de hook.
Não reintroduz `MSHookFunction` em `FBSharedFramework`.
Não mexe em MobileConfig runtime, UIKit ou defaults.
