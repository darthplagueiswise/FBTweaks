#import "FBTFlagCatalog.h"

@implementation FBTFlagCatalog

+ (NSURL *)bundleBaseURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *bases = @[
        @"/var/jb/Library/Application Support/FBTweak.bundle",
        @"/Library/Application Support/FBTweak.bundle",
        [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"FBTweak.bundle"],
    ];
    for (NSString *path in bases) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            return [NSURL fileURLWithPath:path isDirectory:YES];
        }
    }
    return nil;
}

+ (NSURL *)bundleURLForResource:(NSString *)name extension:(NSString *)ext {
    NSURL *base = [self bundleBaseURL];
    if (base) {
        NSURL *candidate = [[base URLByAppendingPathComponent:name] URLByAppendingPathExtension:ext ?: @""];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) return candidate;
    }
    return [[NSBundle mainBundle] URLForResource:name withExtension:ext];
}

+ (id)jsonFromURL:(NSURL *)url {
    if (!url) return nil;
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

+ (NSArray<NSDictionary *> *)flagsNamed:(NSString *)name {
    id root = [self jsonFromURL:[self bundleURLForResource:name extension:@"json"]];
    NSArray *arr = [root isKindOfClass:[NSDictionary class]] ? root[@"params"] : nil;
    return [arr isKindOfClass:[NSArray class]] ? arr : @[];
}

+ (NSArray<NSDictionary *> *)allFlags {
    static NSArray *flags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ flags = [[self flagsNamed:@"FBTFlags"] copy] ?: @[]; });
    return flags;
}

+ (NSArray<NSDictionary *> *)headlineFlags {
    static NSArray *flags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ flags = [[self flagsNamed:@"FBTHeadlineFlags"] copy] ?: @[]; });
    return flags;
}

+ (NSDictionary *)bestMatchForMobileConfigKey:(uint64_t)key {
    if (!key) return nil;
    uint64_t low48 = key & 0x0000FFFFFFFFFFFFULL;
    uint64_t low32 = key & 0xFFFFFFFFULL;
    for (NSDictionary *f in [self allFlags]) {
        NSNumber *sidN = f[@"sid"];
        NSNumber *pidN = f[@"pid"];
        if (![sidN isKindOfClass:[NSNumber class]]) continue;
        uint64_t sid = sidN.unsignedLongLongValue;
        if (sid == key || sid == low48 || sid == low32) return f;
        // Fallback fraco: alguns dumps antigos expõem só paramId. Não usamos
        // para aplicar override, só para rotular a linha capturada.
        if ([pidN isKindOfClass:[NSNumber class]] && pidN.unsignedLongLongValue == low32) {
            return f;
        }
    }
    return nil;
}

+ (NSArray<NSDictionary *> *)queryConfigs {
    static NSArray *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = [self bundleBaseURL];
        NSURL *dir = [base URLByAppendingPathComponent:@"QueryConfigs" isDirectory:YES];
        NSMutableArray *out = [NSMutableArray array];
        NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:nil] ?: @[];
        for (NSURL *url in files) {
            if (![url.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
            id root = [self jsonFromURL:url];
            if (![root isKindOfClass:[NSDictionary class]]) continue;
            for (NSString *name in [(NSDictionary *)root allKeys]) {
                if ([name hasPrefix:@"$"]) continue;
                id q = root[name];
                NSMutableDictionary *entry = nil;
                if ([q isKindOfClass:[NSDictionary class]]) {
                    entry = [NSMutableDictionary dictionaryWithDictionary:q];
                } else {
                    entry = [NSMutableDictionary dictionary];
                    entry[@"id"] = @"computed";
                    entry[@"value"] = [q description] ?: @"";
                    entry[@"variables"] = @[];
                }
                entry[@"name"] = name;
                entry[@"file"] = url.lastPathComponent ?: @"";
                [out addObject:entry];
            }
        }
        [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
        }];
        items = [out copy];
    });
    return items ?: @[];
}

@end
