#import "FBGRGateStore.h"
#import "../FBGramPrefix.h"

// Override store: slotId (uint64_t) → forced BOOL.
// slotId 0 is LEGITIMATE (4 bool params in v563 use it). The previous build
// dropped it in FBGRGateAllOverrideSlotIds via `slotId > 0`, so the only
// legit slot-0 bool never persisted. Fixed: we track presence via objectForKey
// (nil check), which works for slot 0, and the "all" list does NOT filter 0.

static NSString *FBGRSlotKey(uint64_t slotId) {
    return [NSString stringWithFormat:@"fbgr.slot.%llu", (unsigned long long)slotId];
}

BOOL FBGRGateIsSet(uint64_t slotId) {
    return [FBGRPrefs() objectForKey:FBGRSlotKey(slotId)] != nil;
}
BOOL FBGRGateGet(uint64_t slotId) {
    return [FBGRPrefs() boolForKey:FBGRSlotKey(slotId)];
}
void FBGRGateSet(uint64_t slotId, BOOL value) {
    [FBGRPrefs() setBool:value forKey:FBGRSlotKey(slotId)];
    [FBGRPrefs() synchronize];
}
void FBGRGateClear(uint64_t slotId) {
    [FBGRPrefs() removeObjectForKey:FBGRSlotKey(slotId)];
    [FBGRPrefs() synchronize];
}
void FBGRGateClearAll(void) {
    NSDictionary *all = [FBGRPrefs() dictionaryRepresentation];
    for (NSString *k in all.allKeys)
        if ([k hasPrefix:@"fbgr.slot."]) [FBGRPrefs() removeObjectForKey:k];
    [FBGRPrefs() synchronize];
}
NSArray<NSNumber *> *FBGRGateAllOverrideSlotIds(void) {
    NSDictionary *all = [FBGRPrefs() dictionaryRepresentation];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *k in all.allKeys) {
        if (![k hasPrefix:@"fbgr.slot."]) continue;
        NSString *suffix = [k substringFromIndex:10];   // after "fbgr.slot."
        if (suffix.length == 0) continue;
        // Validate the suffix is all digits so we never coerce junk to slot 0
        BOOL digits = YES;
        for (NSUInteger i = 0; i < suffix.length; i++) {
            unichar c = [suffix characterAtIndex:i];
            if (c < '0' || c > '9') { digits = NO; break; }
        }
        if (!digits) continue;
        uint64_t slotId = (uint64_t)strtoull(suffix.UTF8String, NULL, 10);
        [result addObject:@(slotId)];   // slot 0 included — it is valid
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}
