#import "FBGRGateStore.h"
#import "../FBGramPrefix.h"
#import <string.h>

#define FBGR_MAX_OVERRIDES 20000
#define FBGR_SLOT_PREFIX @"fbgr.slot."
#define FBGR_SLOT_PREFIX_LENGTH 10

typedef struct { uint64_t slotId; BOOL isSet; BOOL value; } FBGRGateEntry;
static FBGRGateEntry gEntries[FBGR_MAX_OVERRIDES];
static NSUInteger gEntryCount = 0;
static BOOL gWarm = NO;

static NSString *FBGRSlotKey(uint64_t slotId) {
    return [NSString stringWithFormat:@"%@%llu", FBGR_SLOT_PREFIX, (unsigned long long)slotId];
}

static NSInteger FBGRFind(uint64_t slotId) {
    for (NSUInteger i = 0; i < gEntryCount; i++) {
        if (gEntries[i].isSet && gEntries[i].slotId == slotId) return (NSInteger)i;
    }
    return -1;
}

static void FBGRGateWarmCacheFromPrefsLocked(void) {
    gEntryCount = 0;

    NSDictionary *all = [FBGRPrefs() dictionaryRepresentation] ?: @{};
    for (NSString *key in all.allKeys) {
        if (![key isKindOfClass:NSString.class] || ![key hasPrefix:FBGR_SLOT_PREFIX]) continue;
        if (key.length <= FBGR_SLOT_PREFIX_LENGTH || gEntryCount >= FBGR_MAX_OVERRIDES) continue;

        NSString *slotString = [key substringFromIndex:FBGR_SLOT_PREFIX_LENGTH];
        uint64_t slotId = (uint64_t)[slotString unsignedLongLongValue];
        if (slotId == 0 && ![slotString isEqualToString:@"0"]) continue;

        gEntries[gEntryCount++] = (FBGRGateEntry){ slotId, YES, [FBGRPrefs() boolForKey:key] };
    }

    gWarm = YES;
}

static void FBGREnsureWarmLocked(void) {
    if (!gWarm) FBGRGateWarmCacheFromPrefsLocked();
}

void FBGRGateWarmCacheFromPrefs(void) {
    @synchronized(FBGRPrefs()) {
        FBGRGateWarmCacheFromPrefsLocked();
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
        FBGREnsureWarmLocked();

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
        FBGREnsureWarmLocked();

        NSInteger i = FBGRFind(slotId);
        if (i >= 0) {
            if ((NSUInteger)i + 1 < gEntryCount) {
                memmove(&gEntries[i], &gEntries[i + 1], (gEntryCount - (NSUInteger)i - 1) * sizeof(FBGRGateEntry));
            }
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
        for (NSString *key in all.allKeys) {
            if ([key isKindOfClass:NSString.class] && [key hasPrefix:FBGR_SLOT_PREFIX]) {
                [FBGRPrefs() removeObjectForKey:key];
            }
        }

        [FBGRPrefs() synchronize];
        gEntryCount = 0;
        gWarm = YES;
    }
}

NSArray<NSNumber *> *FBGRGateAllOverrideSlotIds(void) {
    @synchronized(FBGRPrefs()) {
        FBGREnsureWarmLocked();

        NSMutableArray *ids = [NSMutableArray arrayWithCapacity:gEntryCount];
        for (NSUInteger i = 0; i < gEntryCount; i++) {
            if (gEntries[i].isSet) [ids addObject:@(gEntries[i].slotId)];
        }

        return [ids sortedArrayUsingSelector:@selector(compare:)];
    }
}
