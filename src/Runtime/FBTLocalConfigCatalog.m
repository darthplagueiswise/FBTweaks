#import "FBTLocalConfigCatalog.h"
#import "FBTFlagCatalog.h"
#include <zlib.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <mach/mach.h>

static NSArray *sConfigurations;
static NSDictionary *sPackedLabels;
static NSDictionary *sSchemaLabels;

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
        NSMutableDictionary *schemaIndex = [NSMutableDictionary dictionary];
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
                        NSString *schemaKey = [NSString stringWithFormat:@"%@:%ld:%llu:%@", unit, (long)ordinal, pid, type];
                        schemaIndex[schemaKey] = index[key];
                    }
                }
            }
        }
        [configs sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
        }];
        @synchronized(self) { sPackedLabels = [index copy]; sSchemaLabels = [schemaIndex copy]; sConfigurations = [configs copy]; }
    });
    return sConfigurations ?: @[];
}
+ (NSDictionary *)labelForPackedKey:(uint64_t)key {
    uint16_t flags = key >> 48;
    NSString *type = @{@1: @"bool", @2: @"int64", @3: @"string", @4: @"double"}[@(flags & 7)];
    if (!type) return nil;
    NSString *lookup = [NSString stringWithFormat:@"%u:%u:%u:%@:%u", (flags >> 6) & 31,
        (unsigned)((key >> 32) & 0xffff), (unsigned)((key >> 16) & 0xffff), type, (unsigned)(key & 0xffff)];
    @synchronized(self) {
        if (sPackedLabels[lookup]) return sPackedLabels[lookup];
        NSString *schemaKey = [NSString stringWithFormat:@"%u:%u:%u:%@", (flags >> 6) & 31,
            (unsigned)((key >> 32) & 0xffff), (unsigned)((key >> 16) & 0xffff), type];
        NSDictionary *label = sSchemaLabels[schemaKey];
        if (!label) return nil;
        NSMutableDictionary *result = [label mutableCopy];
        result[@"catalogSlot"] = label[@"sid"];
        result[@"sid"] = @(key & 0xffff);
        result[@"slotDiffersFromMap"] = @YES;
        return result;
    }
}
+ (NSNumber *)packedKeyForConfiguration:(NSDictionary *)configuration parameter:(NSDictionary *)parameter {
    NSString *source = configuration[@"source"];
    BOOL primary = [source isEqualToString:@"params_map.txt"];
    BOOL admin = [source isEqualToString:@"params_map_kMobileConfigAdminId.txt"];
    if (!primary && !admin) return nil; // RN slot IDs are not native packed keys.
    NSString *name = configuration[@"name"];
    if (![name isKindOfClass:NSString.class] || !name.length) return nil;
    void *symbol = dlsym(RTLD_DEFAULT, name.UTF8String);
    if (!symbol) return nil;
    NSUInteger count = [configuration[@"params"] count];
    if (count > 65536) return nil;
    unsigned int expectedType = [@{@"bool": @1, @"int64": @2, @"string": @3, @"double": @4}[parameter[@"type"]] unsignedIntValue];
    if (!expectedType) return nil;
    for (NSUInteger i = 0; i < count; ++i) {
        uint64_t key = 0; vm_size_t copied = 0;
        kern_return_t result = vm_read_overwrite(mach_task_self(),
            (vm_address_t)(uintptr_t)symbol + i * sizeof(key), sizeof(key),
            (vm_address_t)(uintptr_t)&key, &copied);
        if (result != KERN_SUCCESS || copied != sizeof(key)) return nil;
        unsigned int flags = (unsigned int)(key >> 48), unit = (flags >> 6) & 31;
        if (((key >> 32) & 0xffff) != [configuration[@"ordinal"] unsignedIntValue]) return nil;
        if ((admin && unit != 4) || (primary && unit != 1 && unit != 2)) return nil;
        if (((key >> 16) & 0xffff) != [parameter[@"id"] unsignedIntValue]) continue;
        if ((flags & 7) != expectedType) return nil;
        // Preserve every flag bit from the live descriptor. Do not synthesize
        // a key from a numeric ID or the map slot. The supplied v2 maps and
        // compiled descriptors have different slots for some identical IDs.
        // Native context readers perform their own specifier translation.
        return @(key);
    }
    return nil;
}
@end

