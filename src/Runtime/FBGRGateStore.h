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
//   - slotId 0 is valid for one bool param in current metadata. Non-bool slot 0 rows are filtered by MCCatalog/UI, not by this store.

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
