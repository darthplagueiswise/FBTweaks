#import "FBGRMCCatalog.h"
#import "../FBGramPrefix.h"
#import <zlib.h>

@implementation FBGRMCParam
- (NSString *)description { return [NSString stringWithFormat:@"<FBGRMCParam slotId=%llu %@>", (unsigned long long)self.slotId, self.fullKey]; }
@end

@interface FBGRMCCatalog ()
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, FBGRMCParam *> *bySlotId;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *sorted;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *boolOnly;
@property(nonatomic, strong) NSArray<FBGRMCParam *> *iOSBool;
@property(nonatomic) BOOL loaded;
@property(nonatomic, copy) NSString *sourcePathMutable;
@end

@implementation FBGRMCCatalog
+ (instancetype)shared { static FBGRMCCatalog *s; static dispatch_once_t o; dispatch_once(&o, ^{ s=[self new]; }); return s; }

static NSData *FBGRGunzip(NSData *compressed) {
    if (!compressed.length) return nil;
    z_stream strm; memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef *)compressed.bytes; strm.avail_in = (uInt)compressed.length;
    if (inflateInit2(&strm, 16 + MAX_WBITS) != Z_OK) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:MAX((NSUInteger)8192, compressed.length * 8)];
    int status = Z_OK;
    while (status == Z_OK) {
        if (strm.total_out >= out.length) [out increaseLengthBy:MAX((NSUInteger)8192, compressed.length * 4)];
        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);
        status = inflate(&strm, Z_SYNC_FLUSH);
    }
    inflateEnd(&strm);
    if (status != Z_STREAM_END) return nil;
    out.length = strm.total_out;
    return out;
}

static void FBGRAddPath(NSMutableArray<NSString *> *paths, NSString *path) { if (path.length && ![paths containsObject:path]) [paths addObject:path]; }
static void FBGRCollectMetadataFiles(NSMutableArray<NSString *> *paths, NSString *dir, NSUInteger depth) {
    if (!dir.length || depth > 2) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO; if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) return;
    for (NSString *name in ([fm contentsOfDirectoryAtPath:dir error:nil] ?: @[])) {
        NSString *p = [dir stringByAppendingPathComponent:name];
        BOOL childDir = NO; [fm fileExistsAtPath:p isDirectory:&childDir];
        NSString *low = name.lowercaseString;
        if ([low hasPrefix:@"reactmobileconfigmetadata"] && ([low hasSuffix:@".json"] || [low hasSuffix:@".json.gz"])) FBGRAddPath(paths, p);
        if (childDir && depth < 2 && ([low containsString:@"fbtweaks"] || [low containsString:@"runtime"] || [low containsString:@"config"])) FBGRCollectMetadataFiles(paths, p, depth + 1);
    }
}

static NSData *FBGRReadMetadataPath(NSString *path, NSString **sourceOut) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    if ([path.lowercaseString hasSuffix:@".gz"]) data = FBGRGunzip(data);
    if (data.length && sourceOut) *sourceOut = path;
    return data;
}

- (void)loadIfNeeded { @synchronized(self) { if (self.loaded) return; [self _load]; self.loaded = YES; } }
- (void)_load {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    if (bundlePath.length) {
        FBGRAddPath(paths, [bundlePath stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json"]);
        FBGRAddPath(paths, [bundlePath stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json.gz"]);
        FBGRCollectMetadataFiles(paths, bundlePath, 0);
    }
    FBGRAddPath(paths, @"/private/var/containers/Bundle/Application/5C38EEAB-1818-4C68-BF7D-A13378A902C2/Facebook.app/ReactMobileConfigMetadata.json");
    FBGRAddPath(paths, @"/private/var/containers/Bundle/Application/5C38EEAB-1818-4C68-BF7D-A13378A902C2/Facebook.app/ReactMobileConfigMetadata.json.gz");
    NSString *home = NSHomeDirectory();
    for (NSString *rel in @[@"Documents/FBTweaks/runtime", @"Documents/FBTweaks", @"Library/Application Support/FBTweaks/runtime", @"Library/Application Support/FBTweaks", @"Library/Caches/FBTweaks/runtime", @"Library/Caches/FBTweaks", @"tmp/FBTweaks/runtime", @"tmp/FBTweaks"]) {
        NSString *dir = [home stringByAppendingPathComponent:rel];
        FBGRAddPath(paths, [dir stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json"]);
        FBGRAddPath(paths, [dir stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json.gz"]);
        FBGRCollectMetadataFiles(paths, dir, 0);
    }
    for (NSString *base in @[@"/Library/Application Support/FBTweaks/runtime", @"/var/jb/Library/Application Support/FBTweaks/runtime", @"/var/mobile/Library/Application Support/FBTweaks/runtime"]) {
        FBGRAddPath(paths, [base stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json"]);
        FBGRAddPath(paths, [base stringByAppendingPathComponent:@"ReactMobileConfigMetadata.json.gz"]);
        FBGRCollectMetadataFiles(paths, base, 0);
    }
    NSString *bundleJson = [NSBundle.mainBundle pathForResource:@"ReactMobileConfigMetadata" ofType:@"json"];
    NSString *bundleGz = [NSBundle.mainBundle pathForResource:@"ReactMobileConfigMetadata" ofType:@"json.gz"];
    FBGRAddPath(paths, bundleJson); FBGRAddPath(paths, bundleGz);
    NSString *source = nil; NSData *data = nil;
    for (NSString *p in paths) { data = FBGRReadMetadataPath(p, &source); if (data.length) break; }
    self.sourcePathMutable = source ?: @"(not found)";
    if (!data.length) { self.bySlotId=[NSMutableDictionary dictionary]; self.sorted=@[]; self.boolOnly=@[]; self.iOSBool=@[]; FBGRLog(@"MCCatalog: no metadata found"); return; }
    NSError *err=nil; NSDictionary *root=[NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    NSDictionary *schema = [root isKindOfClass:NSDictionary.class] ? root[@"schema"] : nil;
    if (![schema isKindOfClass:NSDictionary.class]) { self.bySlotId=[NSMutableDictionary dictionary]; self.sorted=@[]; self.boolOnly=@[]; self.iOSBool=@[]; FBGRLog(@"MCCatalog: invalid JSON %@ source=%@", err, source); return; }
    NSMutableDictionary *bySlot=[NSMutableDictionary dictionaryWithCapacity:schema.count]; NSMutableArray *all=[NSMutableArray arrayWithCapacity:schema.count];
    for (NSString *fullKey in schema) {
        NSDictionary *v=schema[fullKey]; if (![v isKindOfClass:NSDictionary.class]) continue;
        FBGRMCParam *p=[FBGRMCParam new];
        p.slotId=(uint64_t)[v[@"slotId"] unsignedLongLongValue]; p.configKey=(uint64_t)[v[@"configKey"] unsignedLongLongValue];
        p.fullKey=fullKey; p.type=v[@"type"] ?: @""; p.unitType=[v[@"unitType"] integerValue]; p.defaultBool=[v[@"defaultValue"] boolValue];
        NSRange colon=[fullKey rangeOfString:@":"]; if (colon.location != NSNotFound) { p.group=[fullKey substringToIndex:colon.location]; p.paramName=[fullKey substringFromIndex:colon.location+1]; } else { p.group=fullKey; p.paramName=fullKey; }
        bySlot[@(p.slotId)] = p; [all addObject:p];
    }
    self.bySlotId=bySlot;
    self.sorted=[all sortedArrayUsingComparator:^NSComparisonResult(FBGRMCParam *a, FBGRMCParam *b){ return [@(a.slotId) compare:@(b.slotId)]; }];
    self.boolOnly=[self.sorted filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _){ return [p.type isEqualToString:@"boolValue"]; }]];
    self.iOSBool=[self.boolOnly filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _){ return p.unitType == 4; }]];
    FBGRLog(@"MCCatalog: loaded %lu params (%lu bool, %lu iOS bool) source=%@", (unsigned long)self.sorted.count, (unsigned long)self.boolOnly.count, (unsigned long)self.iOSBool.count, source);
}
- (FBGRMCParam *)paramForSlotId:(uint64_t)slotId { if (!self.loaded) [self loadIfNeeded]; return self.bySlotId[@(slotId)]; }
- (NSArray<FBGRMCParam *> *)allParams { if (!self.loaded) [self loadIfNeeded]; return self.sorted ?: @[]; }
- (NSArray<FBGRMCParam *> *)boolParams { if (!self.loaded) [self loadIfNeeded]; return self.boolOnly ?: @[]; }
- (NSArray<FBGRMCParam *> *)iOSBoolParams { if (!self.loaded) [self loadIfNeeded]; return self.iOSBool ?: @[]; }
- (NSArray<FBGRMCParam *> *)searchParams:(NSString *)q { if (!self.loaded) [self loadIfNeeded]; if (!q.length) return self.sorted ?: @[]; NSString *low=q.lowercaseString; return [self.sorted filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(FBGRMCParam *p, id _){ return [p.fullKey.lowercaseString containsString:low]; }]]; }
- (NSUInteger)totalCount { return self.sorted.count; }
- (BOOL)isLoaded { return self.loaded; }
- (NSString *)sourcePath { return self.sourcePathMutable ?: @""; }
@end
