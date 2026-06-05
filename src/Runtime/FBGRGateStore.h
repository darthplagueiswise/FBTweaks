#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
BOOL FBGRGateIsSet(uint64_t slotId);
BOOL FBGRGateGet(uint64_t slotId);
void FBGRGateSet(uint64_t slotId, BOOL value);
void FBGRGateClear(uint64_t slotId);
void FBGRGateClearAll(void);
void FBGRGateWarmCacheFromPrefs(void);
NSArray<NSNumber *> *FBGRGateAllOverrideSlotIds(void);

void FBGRGateRememberRuntimeHook(NSString *className, NSString *selectorName, BOOL classMethod);
void FBGRGateForgetRuntimeHook(NSString *className, NSString *selectorName, BOOL classMethod);
NSArray<NSDictionary *> *FBGRGateAllRuntimeHookSpecs(void);
NSUInteger FBGRGateRuntimeHookSpecCount(void);
NSString *FBGRGateDiagnostic(void);
#ifdef __cplusplus
}
#endif
