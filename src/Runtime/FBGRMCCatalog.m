#import "FBGRMCCatalog.h"
#import "../FBGramPrefix.h"

// Secondary keyword tags derived from the fullKey. Group-based categories come
// from the JSON `group` field directly; these tags are an orthogonal axis so a
// param can show up under e.g. both "gaming" group and "dogfood" tag.
static NSArray<NSString *> *FBGRTagsForKey(NSString *key) {
    NSString *k = key.lowercaseString;
    NSMutableArray *tags = [NSMutableArray array];
    struct { const char *needle; const char *tag; } map[] = {
        {"is_employee",   "employee"},
        {"employee",      "employee"},
        {"is_internal",   "internal"},
        {"internal",      "internal"},
        {"dogfood",       "dogfood"},
        {"liquid_glass",  "liquid_glass"},
        {"navigation",    "navigation"},
        {"tab_bar",       "navigation"},
        {"floating",      "navigation"},
        {"marketplace",   "marketplace"},
        {"gaming",        "gaming"},
        {"dlp",           "dlp"},
        {"debug",         "debug"},
        {NULL, NULL}
    };
    for (int i = 0; map[i].needle; i++) {
        NSString *needle = @(map[i].needle);
        NSString *tag = @(map[i].tag);
        if ([k containsString:needle] && ![tags containsObject:tag])
            [tags addObject:tag];
    }
    return tags;
}

@interface FBGRMCParam ()
@property(nonatomic, copy) NSArray<NSString *> *tagsStorage;
@end

@implementation FBGRMCParam
- (BOOL)isBool { return [self.type isEqualToString:@"boolValue"]; }
- (NSArray<NSString *> *)tags {
    if (!self.tagsStorage) self.tagsStorage = FBGRTagsForKey(self.fullKey);
    return self.tagsStorage;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<FBGRMCParam slot=%llu cfg=%llu#%ld %@ (%@)>",
            (unsigned long long)self.slotId, (unsigned long long)self.configKey,
            (long)self.paramId, self.fullKey, self.type];
}
@end

@interface FBGRMCCatalog ()
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, FBGRMCParam *> *bySlotId;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *sorted;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *iOSBool;
@property(nonatomic, strong) NSDictionary<NSString *, NSArray<FBGRMCParam *> *> *byGroup;
@property(nonatomic, strong) NSArray<NSString *> *groups;
@property(nonatomic) BOOL loaded;
@end

@implementation FBGRMCCatalog

+ (instancetype)shared {
    static FBGRMCCatalog *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [self new]; });
    return s;
}

- (void)loadIfNeeded {
    @synchronized(self) {
        if (self.loaded) return;
        [self _load];
        self.loaded = YES;
    }
}

- (void)_emptyOut {
    self.bySlotId = [NSMutableDictionary dictionary];
    self.sorted = @[]; self.iOSBool = @[];
    self.byGroup = @{}; self.groups = @[];
}

- (void)_load {
    // PREFER app's own bundle (works for sideload AND jailbreak). The Facebook
    // .ipa ships ReactMobileConfigMetadata.json at Payload/Facebook.app/ root,
    // byte-identical to what we'd otherwise bundle. Reading the app's copy is
    // signature-safe (read-only access to a signed resource) and avoids
    // version drift since the app's JSON matches the app's binary exactly.
    NSData *data = nil;
    NSString *path = nil;
    NSBundle *main = [NSBundle mainBundle];
    path = [main pathForResource:@"ReactMobileConfigMetadata" ofType:@"json"];
    if (path) data = [NSData dataWithContentsOfFile:path];

    // Fallback 1: explicit FB bundle id (defensive)
    if (!data) {
        NSBundle *fb = [NSBundle bundleWithIdentifier:@"com.facebook.Facebook"];
        path = [fb pathForResource:@"ReactMobileConfigMetadata" ofType:@"json"];
        if (path) data = [NSData dataWithContentsOfFile:path];
    }

    // Fallback 2: jailbreak install path from our .deb
    if (!data) {
        path = @"/Library/Application Support/FBTweaks/runtime/ReactMobileConfigMetadata.json";
        data = [NSData dataWithContentsOfFile:path];
    }

    if (!data) { FBGRLog("MCCatalog: no data"); [self _emptyOut]; return; }
    FBGRLog("MCCatalog: loading from %@ (%lu bytes)", path, (unsigned long)data.length);

    NSError *err = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    NSDictionary *schema = [root isKindOfClass:NSDictionary.class] ? root[@"schema"] : nil;
    if (![schema isKindOfClass:NSDictionary.class]) {
        FBGRLog("MCCatalog: bad schema %@", err); [self _emptyOut]; return;
    }

    NSMutableDictionary *bySlot = [NSMutableDictionary dictionaryWithCapacity:schema.count];
    NSMutableArray *all = [NSMutableArray arrayWithCapacity:schema.count];
    NSMutableDictionary<NSString *, NSMutableArray *> *groupMap = [NSMutableDictionary dictionary];

    for (NSString *fullKey in schema) {
        NSDictionary *v = schema[fullKey];
        if (![v isKindOfClass:NSDictionary.class]) continue;

        FBGRMCParam *p = [FBGRMCParam new];
        p.slotId      = (uint64_t)[v[@"slotId"] unsignedLongLongValue];
        p.configKey   = (uint64_t)[v[@"configKey"] unsignedLongLongValue];
        p.paramId     = [v[@"paramId"] integerValue];
        p.fullKey     = fullKey;
        p.type        = v[@"type"] ?: @"";
        p.unitType    = [v[@"unitType"] integerValue];
        p.defaultBool = [v[@"defaultValue"] boolValue];

        NSRange colon = [fullKey rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            p.group     = [fullKey substringToIndex:colon.location];
            p.paramName = [fullKey substringFromIndex:colon.location + 1];
        } else {
            p.group = fullKey; p.paramName = fullKey;
        }

        // Index by slotId; only bools are overrideable so prefer a bool if a
        // collision ever happened (slotIds are unique for bools in practice).
        bySlot[@(p.slotId)] = p;
        [all addObject:p];

        NSMutableArray *g = groupMap[p.group];
        if (!g) { g = [NSMutableArray array]; groupMap[p.group] = g; }
        [g addObject:p];
    }

    self.bySlotId = bySlot;
    self.sorted = [all sortedArrayUsingComparator:^NSComparisonResult(FBGRMCParam *a, FBGRMCParam *b) {
        return [a.fullKey compare:b.fullKey];
    }];
    self.iOSBool = [self.sorted filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return p.unitType == 4 && p.isBool;
        }]];
    self.byGroup = groupMap;
    self.groups = [groupMap.allKeys sortedArrayUsingSelector:@selector(compare:)];

    FBGRLog("MCCatalog: %lu params, %lu iOS-bool, %lu groups",
        (unsigned long)self.sorted.count, (unsigned long)self.iOSBool.count,
        (unsigned long)self.groups.count);
}

- (nullable FBGRMCParam *)paramForSlotId:(uint64_t)slotId {
    [self loadIfNeeded];
    return self.bySlotId[@(slotId)];
}
- (NSArray<FBGRMCParam *> *)allParams { [self loadIfNeeded]; return self.sorted ?: @[]; }
- (NSArray<FBGRMCParam *> *)iOSBoolParams { [self loadIfNeeded]; return self.iOSBool ?: @[]; }
- (NSDictionary *)paramsByGroup { [self loadIfNeeded]; return self.byGroup ?: @{}; }
- (NSArray<NSString *> *)allGroups { [self loadIfNeeded]; return self.groups ?: @[]; }

- (NSArray<FBGRMCParam *> *)paramsWithTag:(NSString *)tag {
    [self loadIfNeeded];
    return [self.sorted filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return [p.tags containsObject:tag];
        }]];
}
- (NSArray<FBGRMCParam *> *)searchParams:(NSString *)q {
    [self loadIfNeeded];
    if (!q.length) return self.sorted ?: @[];
    NSString *low = q.lowercaseString;
    return [self.sorted filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return [p.fullKey.lowercaseString containsString:low];
        }]];
}
- (NSUInteger)totalCount { [self loadIfNeeded]; return self.sorted.count; }
- (BOOL)isLoaded { return self.loaded; }

@end
