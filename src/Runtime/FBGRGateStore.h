#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// Persistent MobileConfig slot override store.
//
// Runtime rule:
//   - NSUserDefaults is used only when menu/toggles mutate state or during warmup.
//   - hook hot paths call FBGRGateIsSet/FBGRGateGet and must hit RAM only.
//   - no NSString/NSUserDefaults allocation in FBGRGateIsSet/FBGRGateGet.
//   - slotId 0 is not a stable key and is intentionally ignored by setters.

void FBGRGateStoreWarmup(void);

BOOL FBGRGateIsSet(uint64_t slotId);
BOOL FBGRGateGet(uint64_t slotId);
void FBGRGateSet(uint64_t slotId, BOOL value);
void FBGRGateClear(uint64_t slotId);
void FBGRGateClearAll(void);
NSUInteger FBGRGateOverrideCount(void);

NSArray<NSNumber *> *FBGRGateAllOverrideSlotIds(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
