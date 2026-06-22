#ifndef FBT_MOBILECONFIG_RUNTIME_H
#define FBT_MOBILECONFIG_RUNTIME_H

#import <Foundation/Foundation.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

extern NSString * const FBTMobileConfigDidUpdateNotification;

void FBTInstallMobileConfigRuntime(void);
void FBTMobileConfigReloadPrefs(void);
NSArray<NSDictionary *> *FBTMobileConfigSnapshot(void);
NSDictionary *FBTMobileConfigOverrideForKey(uint64_t key);
void FBTMobileConfigSetOverride(uint64_t key, NSString *type, id value);
void FBTMobileConfigClearOverride(uint64_t key);
void FBTMobileConfigClearAllOverrides(void);
void FBTMobileConfigRecordAccess(uint64_t key, NSString *type, id defaultValue, id resultValue, BOOL overridden);

#ifdef __cplusplus
}
#endif

#endif /* FBT_MOBILECONFIG_RUNTIME_H */
