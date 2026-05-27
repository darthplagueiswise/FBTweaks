#import "FBGRMCCatalog.h"
#import "../FBGramPrefix.h"

@implementation FBGRMCParam
- (NSString *)description {
    return [NSString stringWithFormat:@"<FBGRMCParam slotId=%llu %@>",
            (unsigned long long)self.slotId, self.fullKey];
}
@end

@interface FBGRMCCatalog ()
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, FBGRMCParam *> *bySlotId;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *sorted;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *iOSBool;
@property(nonatomic) BOOL loaded;
@end

@implementation FBGRMCCatalog

+ (instancetype)shared {
    static FBGRMCCatalog *s;
    static dispatch_once_t o;
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

- (void)_load {
    NSString *path = @"/Library/Application Support/FBTweaks/runtime/ReactMobileConfigMetadata.json";
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        // Fallback: embedded bundle path
        NSBundle *b = [NSBundle bundleWithIdentifier:@"com.facebook.Facebook"];
        path = [b pathForResource:@"ReactMobileConfigMetadata" ofType:@"json"];
        data = path ? [NSData dataWithContentsOfFile:path] : nil;
    }
    if (!data) {
        FBGRLog("MCCatalog: no data found at %@", path ?: @"(nil)");
        self.bySlotId = [NSMutableDictionary dictionary];
        self.sorted   = @[];
        self.iOSBool  = @[];
        return;
    }

    NSError *err = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (!root || err) {
        FBGRLog("MCCatalog: JSON parse error %@", err);
        self.bySlotId = [NSMutableDictionary dictionary];
        self.sorted   = @[];
        self.iOSBool  = @[];
        return;
    }

    NSDictionary *schema = root[@"schema"];
    if (![schema isKindOfClass:NSDictionary.class]) {
        FBGRLog("MCCatalog: no schema key");
        self.bySlotId = [NSMutableDictionary dictionary];
        self.sorted   = @[];
        self.iOSBool  = @[];
        return;
    }

    NSMutableDictionary *bySlot = [NSMutableDictionary dictionaryWithCapacity:schema.count];
    NSMutableArray *all = [NSMutableArray arrayWithCapacity:schema.count];

    for (NSString *fullKey in schema) {
        NSDictionary *v = schema[fullKey];
        if (![v isKindOfClass:NSDictionary.class]) continue;

        FBGRMCParam *p = [FBGRMCParam new];
        p.slotId     = (uint64_t)[v[@"slotId"] unsignedLongLongValue];
        p.configKey  = (uint64_t)[v[@"configKey"] unsignedLongLongValue];
        p.fullKey    = fullKey;
        p.type       = v[@"type"] ?: @"";
        p.unitType   = [v[@"unitType"] integerValue];
        p.defaultBool = [v[@"defaultValue"] boolValue];

        NSRange colon = [fullKey rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            p.group     = [fullKey substringToIndex:colon.location];
            p.paramName = [fullKey substringFromIndex:colon.location + 1];
        } else {
            p.group     = fullKey;
            p.paramName = fullKey;
        }

        bySlot[@(p.slotId)] = p;
        [all addObject:p];
    }

    self.bySlotId = bySlot;
    self.sorted   = [all sortedArrayUsingComparator:^NSComparisonResult(FBGRMCParam *a, FBGRMCParam *b) {
        return [@(a.slotId) compare:@(b.slotId)];
    }];
    self.iOSBool  = [self.sorted filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return p.unitType == 4 && [p.type isEqualToString:@"boolValue"];
        }]];

    FBGRLog("MCCatalog: loaded %lu params (%lu iOS bool)",
        (unsigned long)self.sorted.count, (unsigned long)self.iOSBool.count);
}

- (nullable FBGRMCParam *)paramForSlotId:(uint64_t)slotId {
    if (!self.loaded) [self loadIfNeeded];
    return self.bySlotId[@(slotId)];
}
- (NSArray<FBGRMCParam *> *)allParams {
    if (!self.loaded) [self loadIfNeeded];
    return self.sorted ?: @[];
}
- (NSArray<FBGRMCParam *> *)iOSBoolParams {
    if (!self.loaded) [self loadIfNeeded];
    return self.iOSBool ?: @[];
}
- (NSArray<FBGRMCParam *> *)searchParams:(NSString *)q {
    if (!self.loaded) [self loadIfNeeded];
    if (!q.length) return self.sorted ?: @[];
    NSString *low = q.lowercaseString;
    return [self.sorted filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return [p.fullKey.lowercaseString containsString:low];
        }]];
}
- (NSUInteger)totalCount { return self.sorted.count; }
- (BOOL)isLoaded { return self.loaded; }

@end
