#import "FBGRGateStore.h"
#import "../FBGramPrefix.h"

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
        NSString *suffix = [k substringFromIndex:10];
        uint64_t slotId = (uint64_t)[suffix longLongValue];
        if (slotId > 0) [result addObject:@(slotId)];
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}
