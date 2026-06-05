#import "FBGRMCCatalog.h"
#import "FBGRMCEmbeddedCatalog.h"
#import "../FBGramPrefix.h"
#import <zlib.h>

@implementation FBGRMCParam
@end

static FBGRFeatureCategory FBGRCategorizeKey(NSString *key) {
    NSString *k = key.lowercaseString ?: @"";
    if ([k containsString:@"liquid"] || [k containsString:@"glass"]) return FBGRFeatureCategoryLiquidGlass;
    if ([k containsString:@"tabbar"] || [k containsString:@"tab_bar"] || [k containsString:@"navigation"] || [k containsString:@"nav_bar"]) return FBGRFeatureCategoryTabBar;
    if ([k containsString:@"gemstone"] || [k containsString:@"dating"] || [k containsString:@"match"] || [k containsString:@"crush"]) return FBGRFeatureCategoryDating;
    if ([k containsString:@"dogfood"] || [k containsString:@"dogfooding"] || [k containsString:@"dlp"]) return FBGRFeatureCategoryDogfood;
    if ([k containsString:@"employee"] || [k containsString:@"internal"]) return FBGRFeatureCategoryInternal;
    if ([k containsString:@"debug"] || [k containsString:@"developer"] || [k containsString:@"dev_menu"] || [k containsString:@"diagnostic"]) return FBGRFeatureCategoryDebug;
    if ([k containsString:@"gen_ai"] || [k containsString:@"ai_"] || [k containsString:@"mp_ai"] || [k containsString:@"assistant"] || [k containsString:@"ama_"]) return FBGRFeatureCategoryAI;
    if ([k containsString:@"marketplace"] || [k hasPrefix:@"mp_"]) return FBGRFeatureCategoryMarketplace;
    if ([k containsString:@"experiment"] || [k containsString:@"qe_"] || [k containsString:@"gk_"] || [k containsString:@"test"]) return FBGRFeatureCategoryExperiments;
    if ([k containsString:@"ui"] || [k containsString:@"chrome"] || [k containsString:@"button"] || [k containsString:@"search"] || [k containsString:@"menu"] || [k containsString:@"surface"]) return FBGRFeatureCategoryUI;
    return FBGRFeatureCategoryExperiments;
}

static NSData *FBGRGunzip(NSData *compressed) {
    if (!compressed.length) return nil;
    z_stream strm; memset(&strm, 0, sizeof(strm));
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
    if (inflateEnd(&strm) != Z_OK || status != Z_STREAM_END) return nil;
    out.length = strm.total_out;
    return out;
}

static NSData *FBGRReadPath(NSString *path, NSString **sourceOut) {
    if (!path.length) return nil;
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d.length) return nil;
    if ([path.lowercaseString hasSuffix:@".gz"]) d = FBGRGunzip(d);
    if (d.length && sourceOut) *sourceOut = path;
    return d;
}

static void FBGRAdd(NSMutableArray<NSString *> *a, NSString *p) { if (p.length && ![a containsObject:p]) [a addObject:p]; }

static void FBGRCollect(NSMutableArray<NSString *> *paths, NSString *dir, NSUInteger depth) {
    if (!dir.length || depth > 2) return;
    BOOL isDir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:dir isDirectory:&isDir] || !isDir) return;
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] ?: @[];
    for (NSString *name in items) {
        NSString *low = name.lowercaseString;
        NSString *p = [dir stringByAppendingPathComponent:name];
        BOOL childDir = NO; [NSFileManager.defaultManager fileExistsAtPath:p isDirectory:&childDir];
        if ([low hasPrefix:@"reactmobileconfigmetadata"] && ([low hasSuffix:@".json"] || [low hasSuffix:@".json.gz"])) FBGRAdd(paths, p);
        if (childDir && ([low containsString:@"fbtweaks"] || [low containsString:@"runtime"] || [low containsString:@"config"])) FBGRCollect(paths, p, depth + 1);
    }
}

static NSData *FBGRLoadCatalogData(NSString **sourceOut) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *bundle = NSBundle.mainBundle.bundlePath;
    FBGRAdd(paths, [bundle stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json"]);
    FBGRAdd(paths, [bundle stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json.gz"]);
    FBGRCollect(paths, bundle, 0);
    FBGRAdd(paths, @"/private/var/containers/Bundle/Application/5C38EEAB-1818-4C68-BF7D-A13378A902C2/Facebook.app/ReactMobileConfigMetadata.json");
    FBGRAdd(paths, @"/private/var/containers/Bundle/Application/5C38EEAB-1818-4C68-BF7D-A13378A902C2/Facebook.app/ReactMobileConfigMetadata.json.gz");
    NSString *home = NSHomeDirectory();
    for (NSString *rel in @[@"Documents/FBTweaks", @"Documents/FBTweaks/runtime", @"Library/Application Support/FBTweaks", @"Library/Application Support/FBTweaks/runtime", @"Library/Caches/FBTweaks", @"tmp/FBTweaks"]) {
        NSString *dir = [home stringByAppendingPathComponent:rel];
        FBGRAdd(paths, [dir stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json"]);
        FBGRAdd(paths, [dir stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json.gz"]);
        FBGRCollect(paths, dir, 0);
    }
    for (NSString *base in @[@"/Library/Application Support/FBTweaks/runtime", @"/var/jb/Library/Application Support/FBTweaks/runtime", @"/var/mobile/Library/Application Support/FBTweaks/runtime"]) {
        FBGRAdd(paths, [base stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json"]);
        FBGRAdd(paths, [base stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json.gz"]);
        FBGRCollect(paths, base, 0);
    }
    for (NSString *p in paths) {
        NSData *d = FBGRReadPath(p, sourceOut);
        if (d.length) return d;
    }
    NSData *embedded = FBGRMCEmbeddedCatalogJSONData();
    if (embedded.length && sourceOut) *sourceOut = [NSString stringWithFormat:@"embedded gzip (%lu bytes)", (unsigned long)FBGRMCEmbeddedCatalogCompressedSize()];
    return embedded;
}

@interface FBGRMCCatalog ()
@property(nonatomic, assign) BOOL loaded;
@property(nonatomic, copy) NSString *sourceDescription;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *boolParams;
@property(nonatomic, strong) NSDictionary<NSNumber *, FBGRMCParam *> *bySlot;
@end

@implementation FBGRMCCatalog
+ (instancetype)shared { static FBGRMCCatalog *s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [self new]; }); return s; }

- (void)loadIfNeeded {
    if (self.loaded) return;
    NSString *source = nil;
    NSData *data = FBGRLoadCatalogData(&source);
    if (!data.length) { self.loaded = YES; self.boolParams = @[]; self.bySlot = @{}; self.sourceDescription = @"missing"; return; }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *schema = [json isKindOfClass:NSDictionary.class] ? json[@"schema"] : nil;
    if (![schema isKindOfClass:NSDictionary.class]) schema = json;
    NSMutableArray *arr = [NSMutableArray array];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    [schema enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *v, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || ![v isKindOfClass:NSDictionary.class]) return;
        if (![v[@"type"] isEqual:@"boolValue"]) return;
        NSNumber *slot = v[@"slotId"];
        if (![slot respondsToSelector:@selector(unsignedLongLongValue)]) return;
        FBGRMCParam *p = [FBGRMCParam new];
        p.fullKey = key;
        NSArray *parts = [key componentsSeparatedByString:@":"];
        p.group = parts.count ? parts.firstObject : key;
        p.param = parts.count > 1 ? [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@":"] : key;
        p.type = v[@"type"] ?: @"";
        p.unitType = [v[@"unitType"] description] ?: @"";
        p.slotId = slot.unsignedLongLongValue;
        id def = v[@"defaultValue"];
        p.defaultBool = [def respondsToSelector:@selector(boolValue)] ? [def boolValue] : NO;
        p.category = FBGRCategorizeKey(key);
        [arr addObject:p];
        map[@(p.slotId)] = p;
    }];
    [arr sortUsingComparator:^NSComparisonResult(FBGRMCParam *a, FBGRMCParam *b) { return [a.fullKey compare:b.fullKey]; }];
    self.boolParams = arr;
    self.bySlot = map;
    self.sourceDescription = source ?: @"unknown";
    self.loaded = YES;
}

- (FBGRMCParam *)paramForSlotId:(uint64_t)slotId { [self loadIfNeeded]; return self.bySlot[@(slotId)]; }
- (NSArray<FBGRMCParam *> *)paramsForCategory:(FBGRFeatureCategory)cat { return [self search:nil category:cat]; }
- (NSArray<FBGRMCParam *> *)search:(NSString *)query category:(FBGRFeatureCategory)cat {
    [self loadIfNeeded];
    NSString *q = query.lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (FBGRMCParam *p in self.boolParams) {
        if (cat != FBGRFeatureCategoryAll && p.category != cat) continue;
        if (q.length && ![p.fullKey.lowercaseString containsString:q]) continue;
        [out addObject:p];
    }
    return out;
}
@end
