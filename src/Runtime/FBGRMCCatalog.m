#import "FBGRMCCatalog.h"
#import "FBGRMCEmbeddedCatalog.h"
#import "../FBGramPrefix.h"
#import <dlfcn.h>
#import <zlib.h>

@implementation FBGRMCParam
- (NSString *)description {
    return [NSString stringWithFormat:@"<FBGRMCParam slotId=%llu %@>",
            (unsigned long long)self.slotId, self.fullKey];
}
@end

@interface FBGRMCCatalog ()
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, FBGRMCParam *> *bySlotId;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *sorted;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *bools;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *safeBools;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *iOSBool;
@property(nonatomic, copy) NSString *sourceDescription;
@property(nonatomic) BOOL loaded;
@end

@implementation FBGRMCCatalog

+ (instancetype)shared {
    static FBGRMCCatalog *s;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [self new]; });
    return s;
}

static NSData *FBGRGunzipData(NSData *compressed) {
    if (!compressed.length) return nil;
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef *)compressed.bytes;
    strm.avail_in = (uInt)compressed.length;
    if (inflateInit2(&strm, 16 + MAX_WBITS) != Z_OK) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:MAX((NSUInteger)4096, compressed.length * 8)];
    int status = Z_OK;
    while (status == Z_OK) {
        if (strm.total_out >= out.length) [out increaseLengthBy:MAX((NSUInteger)4096, compressed.length * 4)];
        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);
        status = inflate(&strm, Z_SYNC_FLUSH);
    }
    if (inflateEnd(&strm) != Z_OK) return nil;
    if (status != Z_STREAM_END) return nil;
    out.length = strm.total_out;
    return out;
}

static NSString *FBGRDylibDirectory(void) {
    Dl_info info;
    if (dladdr((const void *)&FBGRDylibDirectory, &info) && info.dli_fname) {
        return [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
    }
    return nil;
}

static NSData *FBGRReadCatalogPath(NSString *path, NSString **sourceOut) {
    if (!path.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    if ([path.pathExtension.lowercaseString isEqualToString:@"gz"]) {
        data = FBGRGunzipData(data);
        if (!data.length) return nil;
    }
    if (sourceOut) *sourceOut = path;
    return data;
}

static NSData *FBGRLoadCatalogData(NSString **sourceOut) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSArray<NSString *> *bases = @[
        @"/Library/Application Support/FBTweaks/runtime",
        @"/var/jb/Library/Application Support/FBTweaks/runtime",
        @"/var/mobile/Library/Application Support/FBTweaks/runtime",
    ];
    for (NSString *base in bases) {
        [paths addObject:[base stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json"]];
        [paths addObject:[base stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json.gz"]];
    }

    NSString *dylibDir = FBGRDylibDirectory();
    if (dylibDir.length) {
        for (NSString *rel in @[
            @"ReactMobileConfigMetadata.json",
            @"ReactMobileConfigMetadata.json.gz",
            @"resources/runtime/ReactMobileConfigMetadata.json",
            @"resources/runtime/ReactMobileConfigMetadata.json.gz",
            @"../resources/runtime/ReactMobileConfigMetadata.json",
            @"../resources/runtime/ReactMobileConfigMetadata.json.gz",
        ]) [paths addObject:[dylibDir stringByAppendingPathComponent:rel]];
    }

    NSBundle *main = NSBundle.mainBundle;
    NSString *p = [main pathForResource:@"ReactMobileConfigMetadata" ofType:@"json"];
    if (p) [paths addObject:p];
    p = [main pathForResource:@"ReactMobileConfigMetadata" ofType:@"json.gz"];
    if (p) [paths addObject:p];

    for (NSString *path in paths) {
        NSData *data = FBGRReadCatalogPath(path, sourceOut);
        if (data.length) return data;
    }

    NSData *embedded = FBGRMCEmbeddedCatalogJSONData();
    if (embedded.length) {
        if (sourceOut) *sourceOut = [NSString stringWithFormat:@"embedded gzip (%lu bytes compressed)", (unsigned long)FBGRMCEmbeddedCatalogCompressedSize()];
        return embedded;
    }
    return nil;
}

- (void)loadIfNeeded {
    @synchronized(self) {
        if (self.loaded) return;
        [self _load];
        self.loaded = YES;
    }
}

- (void)_load {
    NSString *source = nil;
    NSData *data = FBGRLoadCatalogData(&source);
    if (!data.length) {
        FBGRLog(@"MCCatalog: no data found");
        self.bySlotId = [NSMutableDictionary dictionary];
        self.sorted   = @[];
        self.bools    = @[];
        self.safeBools = @[];
        self.iOSBool  = @[];
        self.sourceDescription = @"missing";
        return;
    }

    NSError *err = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![root isKindOfClass:NSDictionary.class] || err) {
        FBGRLog(@"MCCatalog: JSON parse error %@ source=%@ bytes=%lu", err, source, (unsigned long)data.length);
        self.bySlotId = [NSMutableDictionary dictionary];
        self.sorted   = @[];
        self.bools    = @[];
        self.safeBools = @[];
        self.iOSBool  = @[];
        self.sourceDescription = source ?: @"parse-error";
        return;
    }

    NSDictionary *schema = root[@"schema"];
    if (![schema isKindOfClass:NSDictionary.class]) {
        FBGRLog(@"MCCatalog: no schema key source=%@", source);
        self.bySlotId = [NSMutableDictionary dictionary];
        self.sorted   = @[];
        self.bools    = @[];
        self.safeBools = @[];
        self.iOSBool  = @[];
        self.sourceDescription = source ?: @"no-schema";
        return;
    }

    NSMutableDictionary *bySlot = [NSMutableDictionary dictionaryWithCapacity:schema.count];
    NSMutableArray *all = [NSMutableArray arrayWithCapacity:schema.count];

    for (NSString *fullKey in schema) {
        NSDictionary *v = schema[fullKey];
        if (![v isKindOfClass:NSDictionary.class]) continue;

        FBGRMCParam *p = [FBGRMCParam new];
        p.slotId      = (uint64_t)[v[@"slotId"] unsignedLongLongValue];
        p.configKey   = (uint64_t)[v[@"configKey"] unsignedLongLongValue];
        p.paramKey    = (uint64_t)[v[@"paramKey"] unsignedLongLongValue];
        p.paramId     = (uint64_t)[v[@"paramId"] unsignedLongLongValue];
        p.configId    = (uint64_t)[v[@"configId"] unsignedLongLongValue];
        p.fullKey     = fullKey ?: @"";
        p.type        = v[@"type"] ?: @"";
        p.unitType    = [v[@"unitType"] integerValue];
        id def        = v[@"defaultValue"];
        p.defaultBool = [def respondsToSelector:@selector(boolValue)] ? [def boolValue] : NO;

        NSRange colon = [p.fullKey rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            p.group     = [p.fullKey substringToIndex:colon.location];
            p.paramName = [p.fullKey substringFromIndex:colon.location + 1];
        } else {
            p.group     = p.fullKey;
            p.paramName = p.fullKey;
        }

        if (p.slotId > 0 && [p.type isEqualToString:@"boolValue"]) bySlot[@(p.slotId)] = p;
        [all addObject:p];
    }

    self.bySlotId = bySlot;
    self.sorted   = [all sortedArrayUsingComparator:^NSComparisonResult(FBGRMCParam *a, FBGRMCParam *b) {
        NSComparisonResult r = [@(a.slotId) compare:@(b.slotId)];
        if (r != NSOrderedSame) return r;
        return [a.fullKey compare:b.fullKey];
    }];
    self.bools = [self.sorted filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return [p.type isEqualToString:@"boolValue"];
        }]];
    self.safeBools = [self.bools filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return p.slotId > 0;
        }]];
    self.iOSBool  = [self.bools filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return p.unitType == 4 && p.slotId > 0;
        }]];
    self.sourceDescription = source ?: @"unknown";

    FBGRLog(@"MCCatalog: loaded %lu params (%lu bool, %lu safe bool, %lu iOS bool) source=%@",
        (unsigned long)self.sorted.count,
        (unsigned long)self.bools.count,
        (unsigned long)self.safeBools.count,
        (unsigned long)self.iOSBool.count,
        self.sourceDescription);
}

- (nullable FBGRMCParam *)paramForSlotId:(uint64_t)slotId {
    if (!self.loaded) [self loadIfNeeded];
    if (slotId == 0) return nil;
    return self.bySlotId[@(slotId)];
}
- (NSArray<FBGRMCParam *> *)allParams { if (!self.loaded) [self loadIfNeeded]; return self.sorted ?: @[]; }
- (NSArray<FBGRMCParam *> *)boolParams { if (!self.loaded) [self loadIfNeeded]; return self.bools ?: @[]; }
- (NSArray<FBGRMCParam *> *)safeBoolParams { if (!self.loaded) [self loadIfNeeded]; return self.safeBools ?: @[]; }
- (NSArray<FBGRMCParam *> *)iOSBoolParams { if (!self.loaded) [self loadIfNeeded]; return self.iOSBool ?: @[]; }
- (NSArray<FBGRMCParam *> *)searchParams:(NSString *)q {
    if (!self.loaded) [self loadIfNeeded];
    if (!q.length) return self.sorted ?: @[];
    NSString *low = q.lowercaseString;
    return [self.sorted filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _) {
            return [p.fullKey.lowercaseString containsString:low]
                || [[NSString stringWithFormat:@"%llu", (unsigned long long)p.slotId] containsString:low]
                || [[NSString stringWithFormat:@"%llu", (unsigned long long)p.configKey] containsString:low];
        }]];
}
- (NSUInteger)totalCount { if (!self.loaded) [self loadIfNeeded]; return self.sorted.count; }
- (NSUInteger)boolCount { if (!self.loaded) [self loadIfNeeded]; return self.bools.count; }
- (NSUInteger)safeBoolCount { if (!self.loaded) [self loadIfNeeded]; return self.safeBools.count; }
- (NSUInteger)iOSBoolCount { if (!self.loaded) [self loadIfNeeded]; return self.iOSBool.count; }
- (NSString *)catalogSource { if (!self.loaded) [self loadIfNeeded]; return self.sourceDescription ?: @"unknown"; }
- (BOOL)isLoaded { return self.loaded; }

@end
