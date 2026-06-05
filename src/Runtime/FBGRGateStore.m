#import "FBGRGateStore.h"
#import "../FBGramPrefix.h"
#import <string.h>

#define FBGR_MAX_OVERRIDES 16384

typedef struct { uint64_t slotId; BOOL isSet; BOOL value; } FBGRGateEntry;
static FBGRGateEntry gEntries[FBGR_MAX_OVERRIDES];
static NSUInteger gEntryCount = 0;
static BOOL gWarm = NO;

static NSString *FBGRSlotKey(uint64_t slotId) {
    return [NSString stringWithFormat:@"fbgr.slot.%llu", (unsigned long long)slotId];
}

static NSInteger FBGRFind(uint64_t slotId) {
    for (NSUInteger i = 0; i < gEntryCount; i++) if (gEntries[i].isSet && gEntries[i].slotId == slotId) return (NSInteger)i;
    return -1;
}

void FBGRGateWarmCacheFromPrefs(void) {
    @synchronized(FBGRPrefs()) {
        gEntryCount = 0;
        NSDictionary *all = [FBGRPrefs() dictionaryRepresentation] ?: @{};
        for (NSString *k in all.allKeys) {
            if (![k isKindOfClass:NSString.class] || ![k hasPrefix:@"fbgr.slot."]) continue;
            if (gEntryCount >= FBGR_MAX_OVERRIDES) break;
            uint64_t slotId = (uint64_t)[[k substringFromIndex:10] longLongValue];
            gEntries[gEntryCount++] = (FBGRGateEntry){slotId, YES, [FBGRPrefs() boolForKey:k]};
        }
        gWarm = YES;
    }
}

BOOL FBGRGateIsSet(uint64_t slotId) {
    NSInteger i = FBGRFind(slotId);
    return i >= 0 && gEntries[i].isSet;
}

BOOL FBGRGateGet(uint64_t slotId) {
    NSInteger i = FBGRFind(slotId);
    return i >= 0 ? gEntries[i].value : NO;
}

void FBGRGateSet(uint64_t slotId, BOOL value) {
    @synchronized(FBGRPrefs()) {
        NSInteger i = FBGRFind(slotId);
        if (i < 0 && gEntryCount < FBGR_MAX_OVERRIDES) {
            i = (NSInteger)gEntryCount++;
            gEntries[i].slotId = slotId;
            gEntries[i].isSet = YES;
        }
        if (i >= 0) gEntries[i].value = value;
        [FBGRPrefs() setBool:value forKey:FBGRSlotKey(slotId)];
        [FBGRPrefs() synchronize];
        gWarm = YES;
    }
}

void FBGRGateClear(uint64_t slotId) {
    @synchronized(FBGRPrefs()) {
        NSInteger i = FBGRFind(slotId);
        if (i >= 0) {
            if ((NSUInteger)i + 1 < gEntryCount) memmove(&gEntries[i], &gEntries[i + 1], (gEntryCount - (NSUInteger)i - 1) * sizeof(FBGRGateEntry));
            gEntryCount--;
        }
        [FBGRPrefs() removeObjectForKey:FBGRSlotKey(slotId)];
        [FBGRPrefs() synchronize];
        gWarm = YES;
    }
}

void FBGRGateClearAll(void) {
    @synchronized(FBGRPrefs()) {
        NSDictionary *all = [FBGRPrefs() dictionaryRepresentation] ?: @{};
        for (NSString *k in all.allKeys) if ([k isKindOfClass:NSString.class] && [k hasPrefix:@"fbgr.slot."]) [FBGRPrefs() removeObjectForKey:k];
        [FBGRPrefs() synchronize];
        gEntryCount = 0;
        gWarm = YES;
    }
}

NSArray<NSNumber *> *FBGRGateAllOverrideSlotIds(void) {
    if (!gWarm) FBGRGateWarmCacheFromPrefs();
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:gEntryCount];
    for (NSUInteger i = 0; i < gEntryCount; i++) if (gEntries[i].isSet) [a addObject:@(gEntries[i].slotId)];
    return [a sortedArrayUsingSelector:@selector(compare:)];
}
