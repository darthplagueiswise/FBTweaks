#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Persistent store for MobileConfig slot overrides.
/// Maps slotId (uint64_t) to a forced BOOL value.
/// Stored in NSUserDefaults suite com.darthplagueiswise.fbtweaks.
/// Key format: "fbgr.slot.<slotId>"

BOOL    FBGRGateIsSet(uint64_t slotId);
BOOL    FBGRGateGet(uint64_t slotId);
void    FBGRGateSet(uint64_t slotId, BOOL value);
void    FBGRGateClear(uint64_t slotId);
void    FBGRGateClearAll(void);

NSArray<NSNumber *> *FBGRGateAllOverrideSlotIds(void);  // returns uint64 as NSNumber

NS_ASSUME_NONNULL_END
