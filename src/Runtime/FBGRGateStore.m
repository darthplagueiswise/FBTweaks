#import "FBGRGateStore.h"
#import "../FBGramPrefix.h"

#define FBGR_GATE_CACHE_CAP 8192

typedef struct {
    uint64_t slotId;
    BOOL set;
    BOOL value;
} FBGRGateCacheEntry;

static FBGRGateCacheEntry gCache[FBGR_GATE_CACHE_CAP];
static volatile uint32_t gCacheCount = 0;
static NSLock *gCacheLock = nil;
static dispatch_once_t gCacheOnce;

static void FBGRGateStoreInit(void) {
    dispatch_once(&gCacheOnce, ^{
        gCacheLock = [NSLock new];
        gCacheCount = 0;
    });
}

static NSString *FBGRSlotKey(uint64_t slotId) {
    return [NSString stringWithFormat:@"fbgr.slot.%llu", (unsigned long long)slotId];
}

static NSInteger FBGRCacheFindUnlocked(uint64_t slotId) {
    uint32_t n = gCacheCount;
    for (uint32_t i = 0; i < n; i++) {
        if (gCache[i].set && gCache[i].slotId == slotId) return (NSInteger)i;
    }
    return -1;
}

static void FBGRCacheSetUnlocked(uint64_t slotId, BOOL value) {
    NSInteger idx = FBGRCacheFindUnlocked(slotId);
    if (idx >= 0) {
        gCache[idx].value = value;
        gCache[idx].set = YES;
        return;
    }
    uint32_t n = gCacheCount;
    if (n >= FBGR_GATE_CACHE_CAP) return;
    gCache[n].slotId = slotId;
    gCache[n].value = value;
    gCache[n].set = YES;
    gCacheCount = n + 1;
}

static void FBGRCacheClearUnlocked(uint64_t slotId) {
    NSInteger idx = FBGRCacheFindUnlocked(slotId);
    if (idx < 0) return;
    uint32_t n = gCacheCount;
    uint32_t u = (uint32_t)idx;
    if (u + 1 < n) gCache[u] = gCache[n - 1];
    if (n > 0) gCacheCount = n - 1;
}

void FBGRGateStoreWarmup(void) {
    FBGRGateStoreInit();

    NSDictionary *all = [FBGRPrefs() dictionaryRepresentation] ?: @{};
    [gCacheLock lock];
    gCacheCount = 0;
    for (NSString *k in all.allKeys) {
        if (![k isKindOfClass:NSString.class]) continue;
        if (![k hasPrefix:@"fbgr.slot."]) continue;
        NSString *suffix = [k substringFromIndex:10];
        if (suffix.length == 0) continue;
        uint64_t slotId = (uint64_t)[suffix longLongValue];
        if (slotId == 0 && ![suffix isEqualToString:@"0"]) continue;
        BOOL value = [FBGRPrefs() boolForKey:k];
        FBGRCacheSetUnlocked(slotId, value);
    }
    [gCacheLock unlock];
}

BOOL FBGRGateIsSet(uint64_t slotId) {
    uint32_t n = gCacheCount;
    for (uint32_t i = 0; i < n; i++) {
        if (gCache[i].set && gCache[i].slotId == slotId) return YES;
    }
    return NO;
}

BOOL FBGRGateGet(uint64_t slotId) {
    uint32_t n = gCacheCount;
    for (uint32_t i = 0; i < n; i++) {
        if (gCache[i].set && gCache[i].slotId == slotId) return gCache[i].value;
    }
    return NO;
}

void FBGRGateSet(uint64_t slotId, BOOL value) {
    FBGRGateStoreInit();
    [FBGRPrefs() setBool:value forKey:FBGRSlotKey(slotId)];
    [FBGRPrefs() synchronize];

    [gCacheLock lock];
    FBGRCacheSetUnlocked(slotId, value);
    [gCacheLock unlock];
}

void FBGRGateClear(uint64_t slotId) {
    FBGRGateStoreInit();
    [FBGRPrefs() removeObjectForKey:FBGRSlotKey(slotId)];
    [FBGRPrefs() synchronize];

    [gCacheLock lock];
    FBGRCacheClearUnlocked(slotId);
    [gCacheLock unlock];
}

void FBGRGateClearAll(void) {
    FBGRGateStoreInit();
    NSDictionary *all = [FBGRPrefs() dictionaryRepresentation] ?: @{};
    for (NSString *k in all.allKeys) {
        if ([k isKindOfClass:NSString.class] && [k hasPrefix:@"fbgr.slot."]) {
            [FBGRPrefs() removeObjectForKey:k];
        }
    }
    [FBGRPrefs() synchronize];

    [gCacheLock lock];
    gCacheCount = 0;
    [gCacheLock unlock];
}

NSUInteger FBGRGateOverrideCount(void) {
    FBGRGateStoreInit();
    return (NSUInteger)gCacheCount;
}

NSArray<NSNumber *> *FBGRGateAllOverrideSlotIds(void) {
    FBGRGateStoreInit();
    NSMutableArray *result = [NSMutableArray array];

    [gCacheLock lock];
    uint32_t n = gCacheCount;
    for (uint32_t i = 0; i < n; i++) {
        if (gCache[i].set) [result addObject:@(gCache[i].slotId)];
    }
    [gCacheLock unlock];

    return [result sortedArrayUsingSelector:@selector(compare:)];
}
