#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Persistent store for MobileConfig slot overrides.
/// Maps slotId (uint64_t) to a forced BOOL value.
/// Stored in NSUserDefaults suite com.darthplagueiswise.fbtweaks.
/// Key format: "fbgr.slot.<slotId>"
///
/// Guard __cplusplus obrigatório: este header é incluído de .xm (C++)
/// e as implementações estão em .m (C). Sem extern "C", o linker C++
/// procura símbolos mangled e não encontra os símbolos C.

#ifdef __cplusplus
extern "C" {
#endif

BOOL    FBGRGateIsSet(uint64_t slotId);
BOOL    FBGRGateGet(uint64_t slotId);
void    FBGRGateSet(uint64_t slotId, BOOL value);
void    FBGRGateClear(uint64_t slotId);
void    FBGRGateClearAll(void);
NSArray<NSNumber *> *FBGRGateAllOverrideSlotIds(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
