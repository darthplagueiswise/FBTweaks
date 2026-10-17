#ifndef FBT_MOBILECONFIG_DEBUG_UI_HOOKS_H
#define FBT_MOBILECONFIG_DEBUG_UI_HOOKS_H
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void FBTInstallMobileConfigDebugUIBootstrap(void);
void FBTInstallMobileConfigDebugUIHooks(void);
NSDictionary *FBTMobileConfigDebugUIHookStatus(void);

#ifdef __cplusplus
}
#endif

#endif /* FBT_MOBILECONFIG_DEBUG_UI_HOOKS_H */
