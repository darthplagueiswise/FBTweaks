#ifndef FBT_NATIVE_MOBILECONFIG_OVERRIDES_H
#define FBT_NATIVE_MOBILECONFIG_OVERRIDES_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Instala somente hooks ObjC de getters de contexto MobileConfig.
// Não usa MSHookFunction em símbolo C / __TEXT assinado.
void FBTInstallNativeMobileConfigContextCapture(void);

// Recebe apenas objetos retornados por dispatch ObjC já validado.
void FBTNativeMobileConfigRegisterContext(id context);

NSUInteger FBTNativeMobileConfigContextCount(void);
NSString *FBTNativeMobileConfigStatus(void);

// Aplica no FBMobileConfigOverridesTable nativo quando há contexto vivo.
// A camada fishhook runtime continua como fallback persistente.
BOOL FBTNativeMobileConfigApplyOverride(uint64_t key, NSString *type, id value);
BOOL FBTNativeMobileConfigRemoveOverride(uint64_t key);

#ifdef __cplusplus
}
#endif

#endif /* FBT_NATIVE_MOBILECONFIG_OVERRIDES_H */
