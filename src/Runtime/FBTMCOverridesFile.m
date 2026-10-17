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
    NSScanner *scanner = [NSScanner scannerWithString:[entry substringToIndex:r.location]];
    NSInteger index;
    return [scanner scanInteger:&index] && scanner.isAtEnd && index >= 0 ? index : -1;
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
    NSRange separator = [configKey rangeOfString:@":"];
    if (separator.location == NSNotFound) return;
    NSString *idText = [configKey substringToIndex:separator.location];
    NSScanner *scanner = [NSScanner scannerWithString:idText]; NSInteger configID;
    if (![scanner scanInteger:&configID] || !scanner.isAtEnd || configID < 0) return;
    [self setValueText:state == FBTMCStateSys ? nil : (state == FBTMCStateOn ? @"true" : @"false")
        forConfigID:configID paramIdx:idx configName:[configKey substringFromIndex:separator.location + 1] paramName:name error:nil];
}

+ (NSString *)valueTextForConfigID:(NSInteger)configID paramIdx:(NSInteger)idx {
    NSDictionary *all = [self loadOverrides];
    NSString *prefix = [NSString stringWithFormat:@"%ld:", (long)configID];
    for (NSString *key in all) {
        if (![key hasPrefix:prefix] || ![all[key] isKindOfClass:[NSArray class]]) continue;
        for (id item in all[key]) {
            if (![item isKindOfClass:[NSString class]] || [self idxOfEntry:item] != idx) continue;
            NSRange first = [item rangeOfString:@":"];
            NSRange second = [item rangeOfString:@":" options:0 range:NSMakeRange(first.location + 1, [item length] - first.location - 1)];
            if (second.location != NSNotFound) {
                NSString *value = [item substringFromIndex:second.location + 1];
                return [value hasPrefix:@" "] ? [value substringFromIndex:1] : value;
            }
        }
    }
    return nil;
}

+ (BOOL)setValueText:(NSString *)value forConfigID:(NSInteger)configID
             paramIdx:(NSInteger)idx configName:(NSString *)configName
            paramName:(NSString *)paramName error:(NSError **)error {
    @synchronized(self) {
        NSString *path = [self path];
        if (!path.length || configID < 0 || idx < 0) {
            if (error) *error = [NSError errorWithDomain:@"FBTLocalConfig" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"O caminho de overrides ainda não foi localizado. Abra MobileConfig nativo e tente novamente."}];
            return NO;
        }
        NSFileManager *fm = NSFileManager.defaultManager;
        BOOL exists = [fm fileExistsAtPath:path];
        NSData *data = exists ? [NSData dataWithContentsOfFile:path options:0 error:error] : nil;
        if (exists && !data) return NO;
        id raw = exists ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error] : @{};
        if (![raw isKindOfClass:[NSDictionary class]]) {
            if (error && !*error) *error = [NSError errorWithDomain:@"FBTLocalConfig" code:2
                userInfo:@{NSLocalizedDescriptionKey: @"O arquivo existente não é um objeto JSON válido. Nenhum valor foi sobrescrito."}];
            return NO;
        }
        NSMutableDictionary *all = [raw mutableCopy];
        NSString *prefix = [NSString stringWithFormat:@"%ld:", (long)configID];
        NSString *target = [NSString stringWithFormat:@"%@%@", prefix, configName ?: @""];
        NSMutableArray *kept = [NSMutableArray array];
        for (NSString *key in [all.allKeys copy]) {
            if (![key hasPrefix:prefix]) continue;
            if (![all[key] isKindOfClass:[NSArray class]]) {
                if (error) *error = [NSError errorWithDomain:@"FBTLocalConfig" code:3 userInfo:@{NSLocalizedDescriptionKey:@"A configuração existente não contém uma lista de parâmetros."}];
                return NO;
            }
            target = key;
            for (id entry in all[key]) {
                if ([entry isKindOfClass:[NSString class]] && [self idxOfEntry:entry] == idx) continue;
                [kept addObject:entry];
            }
            [all removeObjectForKey:key];
        }
        if (value) [kept addObject:[NSString stringWithFormat:@"%ld: %@: %@", (long)idx, paramName ?: @"", value]];
        if (kept.count) all[target] = kept;
        NSData *output = [NSJSONSerialization dataWithJSONObject:all options:0 error:error];
        if (!output || ![fm createDirectoryAtPath:path.stringByDeletingLastPathComponent
                    withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        NSString *backup = [path stringByAppendingString:@".before_local_edit"];
        if (exists && ![fm fileExistsAtPath:backup] && ![fm copyItemAtPath:path toPath:backup error:error]) return NO;
        return [output writeToFile:path options:NSDataWritingAtomic error:error];
    }
}
@end
