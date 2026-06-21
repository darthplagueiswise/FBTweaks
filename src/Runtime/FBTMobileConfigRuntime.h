#ifndef FBT_MOBILECONFIG_RUNTIME_H
#define FBT_MOBILECONFIG_RUNTIME_H

#import <Foundation/Foundation.h>

extern NSString * const FBTMobileConfigDidUpdateNotification;

void FBTInstallMobileConfigRuntime(void);
void FBTMobileConfigReloadPrefs(void);
NSArray<NSDictionary *> *FBTMobileConfigSnapshot(void);
NSDictionary *FBTMobileConfigOverrideForKey(uint64_t key);
void FBTMobileConfigSetOverride(uint64_t key, NSString *type, id value);
void FBTMobileConfigClearOverride(uint64_t key);
void FBTMobileConfigClearAllOverrides(void);

#endif /* FBT_MOBILECONFIG_RUNTIME_H */
