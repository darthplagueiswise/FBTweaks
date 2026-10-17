#import "FBTLocalConfigCatalog.h"
#import "FBTFlagCatalog.h"
#include <zlib.h>
#include <stdlib.h>

static NSArray *sConfigurations;
static NSDictionary *sPackedLabels;

static id FBTLocalJSON(NSData *data) {
    if (data.length >= 2 && ((const unsigned char *)data.bytes)[0] == 0x1f &&
        ((const unsigned char *)data.bytes)[1] == 0x8b) {
        z_stream stream = {0};
        stream.next_in = (Bytef *)data.bytes; stream.avail_in = (uInt)data.length;
        if (inflateInit2(&stream, 15 + 32) != Z_OK) return nil;
        NSMutableData *out = [NSMutableData data];
        int status;
        do {
            unsigned char block[32768];
            stream.next_out = block; stream.avail_out = sizeof(block);
            status = inflate(&stream, Z_NO_FLUSH);
            [out appendBytes:block length:sizeof(block) - stream.avail_out];
        } while (status == Z_OK && out.length < 8 * 1024 * 1024);
        inflateEnd(&stream);
        if (status != Z_STREAM_END) return nil;
        data = out;
    }
    return data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

static unsigned long long FBTHex(NSString *text) { return strtoull(text.UTF8String ?: "", NULL, 16); }

@implementation FBTLocalConfigCatalog
+ (void)prepare {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [self configurations]; });
}
+ (NSArray<NSDictionary *> *)configurations {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *namesURL = [FBTFlagCatalog bundleURLForResource:@"FBTLocalConfigNames.json" extension:@"gz"];
        id rawNames = namesURL ? FBTLocalJSON([NSData dataWithContentsOfURL:namesURL]) : nil;
        NSDictionary *names = [rawNames isKindOfClass:[NSDictionary class]] ? rawNames : @{};
        NSString *directory = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"mobileconfig_res"];
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: @[];
        NSMutableArray *configs = [NSMutableArray array];
        NSMutableDictionary *index = [NSMutableDictionary dictionary];
        NSDictionary *types = @{@4: @"bool", @8: @"int64", @12: @"string", @16: @"double"};
        for (NSString *file in [files sortedArrayUsingSelector:@selector(compare:)]) {
            if (![file hasPrefix:@"params_map"] && ![file hasPrefix:@"rn_params_map"] && ![file hasPrefix:@"added_params_map"]) continue;
            NSString *text = [NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:file]
                                                     encoding:NSUTF8StringEncoding error:nil];
            if (![text hasPrefix:@"v2,"]) continue;
            BOOL primary = [file isEqualToString:@"params_map.txt"];
            BOOL admin = [file isEqualToString:@"params_map_kMobileConfigAdminId.txt"];
            NSString *scope = admin ? @"Page / Admin ID" : (primary ? @"App / Sessionless" : file);
            NSMutableDictionary *config = nil;
            NSMutableArray *params = nil;
            NSMutableDictionary *counters = [NSMutableDictionary dictionary];
            NSInteger ordinal = -1;
            unsigned long long previous = 0;
            for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                if (!line.length || [line hasPrefix:@"v2,"] || [line hasPrefix:@"?"] || [line isEqualToString:@"END"]) continue;
                NSMutableArray *fields = [[line componentsSeparatedByString:@","] mutableCopy];
                while (fields.count < 4) [fields addObject:@""];
                if ([line hasPrefix:@"*"]) {
                    ++ordinal;
                    NSNumber *configID = @(FBTHex(fields[2]));
                    NSDictionary *known = names[configID.stringValue];
                    NSString *nativeName = [fields[0] substringFromIndex:1];
                    NSString *configName = known[@"name"] ?: nativeName;
                    params = [NSMutableArray array];
                    config = [@{@"id": configID, @"name": configName, @"params": params,
                        @"scope": scope, @"source": file, @"ordinal": @(ordinal)} mutableCopy];
                    [configs addObject:config];
                    previous = FBTHex(fields[1]);
                    continue;
                }
                if (!config) continue;
                unsigned long long pid = previous + ([fields[1] length] ? FBTHex(fields[1]) : 1);
                previous = pid;
                NSUInteger flags = [fields[2] length] ? FBTHex(fields[2]) : 4;
                NSString *type = types[@(flags & 28)];
                if (!type) continue;
                NSNumber *slot = [fields[3] length] ? @(FBTHex(fields[3])) : (counters[type] ?: @0);
                counters[type] = @([counters[type] unsignedLongLongValue] + 1);
                NSString *nativeName = fields[0];
                NSString *pidText = [@(pid) stringValue];
                NSString *name = names[[config[@"id"] stringValue]][@"params"][pidText] ?: nativeName;
                NSDictionary *param = @{@"id": @(pid), @"name": name ?: pidText, @"type": type, @"slot": slot};
                [params addObject:param];
                if (primary || admin) {
                    NSArray *units = primary ? @[@1, @2] : @[@4];
                    for (NSNumber *unit in units) {
                        NSString *key = [NSString stringWithFormat:@"%@:%ld:%llu:%@:%@", unit, (long)ordinal, pid, type, slot];
                        index[key] = @{@"c": config[@"name"], @"p": name ?: pidText,
                            @"ck": config[@"id"], @"pid": @(pid), @"sid": slot, @"t": type};
                    }
                }
            }
        }
        [configs sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
        }];
        @synchronized(self) { sPackedLabels = [index copy]; sConfigurations = [configs copy]; }
    });
    return sConfigurations ?: @[];
}
+ (NSDictionary *)labelForPackedKey:(uint64_t)key {
    uint16_t flags = key >> 48;
    NSString *type = @{@1: @"bool", @2: @"int64", @3: @"string", @4: @"double"}[@(flags & 7)];
    if (!type) return nil;
    NSString *lookup = [NSString stringWithFormat:@"%u:%u:%u:%@:%u", (flags >> 6) & 31,
        (unsigned)((key >> 32) & 0xffff), (unsigned)((key >> 16) & 0xffff), type, (unsigned)(key & 0xffff)];
    @synchronized(self) { return sPackedLabels[lookup]; }
}
@end
