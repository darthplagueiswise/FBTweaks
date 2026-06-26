#import "FBTMCOverridesFile.h"
#import "FBTNativeMobileConfigOverrides.h"

@implementation FBTMCOverridesFile

+ (NSString *)path { return FBTNativeMobileConfigOverridesFilePath(); }
+ (BOOL)fileExists { NSString *p = [self path]; return p && [[NSFileManager defaultManager] fileExistsAtPath:p]; }

+ (NSMutableDictionary *)loadOverrides {
    NSString *p = [self path];
    if (!p) return [NSMutableDictionary dictionary];
    NSData *d = [NSData dataWithContentsOfFile:p];
    if (!d) return [NSMutableDictionary dictionary];
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![obj isKindOfClass:NSDictionary.class]) return [NSMutableDictionary dictionary];
    return [(NSDictionary *)obj mutableCopy];
}

+ (void)save:(NSDictionary *)dict {
    NSString *p = [self path];
    if (!p) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:p.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *d = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
    if (d) [d writeToFile:p atomically:YES];
}

// cada entrada do array tem a forma "idx: name: value"
+ (NSInteger)idxOfEntry:(NSString *)entry {
    NSRange r = [entry rangeOfString:@":"];
    if (r.location == NSNotFound) return -1;
    return [[entry substringToIndex:r.location] integerValue];
}

+ (FBTMCState)stateForConfig:(NSString *)configKey paramIdx:(NSInteger)idx {
    NSDictionary *all = [self loadOverrides];
    NSArray *arr = all[configKey];
    if (![arr isKindOfClass:NSArray.class]) return FBTMCStateSys;
    for (NSString *e in arr) {
        if (![e isKindOfClass:NSString.class]) continue;
        if ([self idxOfEntry:e] != idx) continue;
        NSString *low = e.lowercaseString;
        if ([low hasSuffix:@" true"] || [low hasSuffix:@":true"]) return FBTMCStateOn;
        if ([low hasSuffix:@" false"] || [low hasSuffix:@":false"]) return FBTMCStateOff;
        return FBTMCStateOn; // valor não-bool presente => considerado ativo
    }
    return FBTMCStateSys;
}

+ (void)setState:(FBTMCState)state forConfig:(NSString *)configKey paramIdx:(NSInteger)idx name:(NSString *)name {
    NSMutableDictionary *all = [self loadOverrides];
    NSMutableArray *arr = [(all[configKey] ?: @[]) mutableCopy];
    // remove qualquer entrada desse idx
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *e in arr) {
        if ([e isKindOfClass:NSString.class] && [self idxOfEntry:e] == idx) continue;
        [kept addObject:e];
    }
    if (state != FBTMCStateSys) {
        NSString *val = (state == FBTMCStateOn) ? @"true" : @"false";
        [kept addObject:[NSString stringWithFormat:@"%ld: %@: %@", (long)idx, name, val]];
    }
    if (kept.count) all[configKey] = kept; else [all removeObjectForKey:configKey];
    [self save:all];
}
@end
