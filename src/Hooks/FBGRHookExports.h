#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void FBGRMCGateHooksEnsureInstalled(void);
void FBGRMCGateHooksApplyPersistedOverrides(void);
void FBGRMCGateCacheRefresh(void);
NSString *FBGRMCGateHooksDiagnostic(void);

void FBGRLiquidGlassEnsureInstalled(void);
void FBGRLiquidGlassSetForced(BOOL forced);
NSString *FBGRLiquidGlassDiagnostic(void);

BOOL FBGRDogFoodIsEnabled(void);
void FBGRDogFoodSetEnabled(BOOL enabled);
NSString *FBGRDogFoodDiagnostic(void);

void FBGRMCObserverSetEnabled(BOOL enabled);
void FBGRMCObserverEnsureInstalled(void);
void FBGRMCObserverFlush(void);
NSUInteger FBGRMCObserverSlotCount(void);
NSString *FBGRMCObserverDump(void);

#ifdef __cplusplus
}
#endif
