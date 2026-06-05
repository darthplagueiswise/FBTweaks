#import "FBGRGateStore.h"
#import "../FBGramPrefix.h"
#import <string.h>

#define FBGR_MAX_OVERRIDES 32768

static NSString * const kFBGRRuntimeHookIndexKey = @"fbgr.runtime.hook.index.v1";

typedef struct { uint64_t slotId; BOOL isSet; BOOL value; } FBGRGateEntry;
static FBGRGateEntry gEntries[FBGR_MAX_OVERRIDES];
static NSUInteger gEntryCount = 0;
static BOOL gWarm = NO;

static NSString *FBGRSlotKey(uint64_t slotId) {
    return [NSString stringWithFormat:@"fbgr.slot.%llu", (unsigned long long)slotId];
}

static NSString *FBGRRuntimeHookID(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@|%@|%@", classMethod ? @"class" : @"inst", className ?: @"", selectorName ?: @""];
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

BOOL FBGRGateIsSet(uint64_t slotId) { if (!gWarm) FBGRGateWarmCacheFromPrefs(); NSInteger i = FBGRFind(slotId); return i >= 0 && gEntries[i].isSet; }
BOOL FBGRGateGet(uint64_t slotId) { if (!gWarm) FBGRGateWarmCacheFromPrefs(); NSInteger i = FBGRFind(slotId); return i >= 0 ? gEntries[i].value : NO; }

void FBGRGateSet(uint64_t slotId, BOOL value) {
    @synchronized(FBGRPrefs()) {
        if (!gWarm) FBGRGateWarmCacheFromPrefs();
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
        if (!gWarm) FBGRGateWarmCacheFromPrefs();
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
        for (NSString *k in all.allKeys) {
            if (![k isKindOfClass:NSString.class]) continue;
            if ([k hasPrefix:@"fbgr.slot."] || [k hasPrefix:@"fbgr.bool."] || [k hasPrefix:@"fbgr.liquidglass."] || [k isEqualToString:kFBGRRuntimeHookIndexKey]) {
                [FBGRPrefs() removeObjectForKey:k];
            }
        }
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

static NSMutableDictionary *FBGRRuntimeHookIndexMutable(void) {
    NSDictionary *raw = [FBGRPrefs() dictionaryForKey:kFBGRRuntimeHookIndexKey];
    NSMutableDictionary *m = raw ? [raw mutableCopy] : [NSMutableDictionary dictionary];
    return m;
}

void FBGRGateRememberRuntimeHook(NSString *className, NSString *selectorName, BOOL classMethod) {
    if (!className.length || !selectorName.length) return;
    @synchronized(FBGRPrefs()) {
        NSMutableDictionary *m = FBGRRuntimeHookIndexMutable();
        NSString *uid = FBGRRuntimeHookID(className, selectorName, classMethod);
        m[uid] = @{ @"class": className, @"selector": selectorName, @"classMethod": @(classMethod) };
        [FBGRPrefs() setObject:m forKey:kFBGRRuntimeHookIndexKey];
        [FBGRPrefs() synchronize];
    }
}

void FBGRGateForgetRuntimeHook(NSString *className, NSString *selectorName, BOOL classMethod) {
    if (!className.length || !selectorName.length) return;
    @synchronized(FBGRPrefs()) {
        NSMutableDictionary *m = FBGRRuntimeHookIndexMutable();
        [m removeObjectForKey:FBGRRuntimeHookID(className, selectorName, classMethod)];
        [FBGRPrefs() setObject:m forKey:kFBGRRuntimeHookIndexKey];
        [FBGRPrefs() synchronize];
    }
}

NSArray<NSDictionary *> *FBGRGateAllRuntimeHookSpecs(void) {
    NSDictionary *raw = [FBGRPrefs() dictionaryForKey:kFBGRRuntimeHookIndexKey];
    if (![raw isKindOfClass:NSDictionary.class] || raw.count == 0) return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (id v in raw.allValues) if ([v isKindOfClass:NSDictionary.class]) [out addObject:v];
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *sa = [NSString stringWithFormat:@"%@ %@ %@", a[@"class"] ?: @"", a[@"selector"] ?: @"", a[@"classMethod"] ?: @""];
        NSString *sb = [NSString stringWithFormat:@"%@ %@ %@", b[@"class"] ?: @"", b[@"selector"] ?: @"", b[@"classMethod"] ?: @""];
        return [sa compare:sb];
    }];
}

NSUInteger FBGRGateRuntimeHookSpecCount(void) { return FBGRGateAllRuntimeHookSpecs().count; }

NSString *FBGRGateDiagnostic(void) {
    return [NSString stringWithFormat:@"mcOverrides=%lu\nruntimeHookSpecs=%lu", (unsigned long)FBGRGateAllOverrideSlotIds().count, (unsigned long)FBGRGateRuntimeHookSpecCount()];
}
