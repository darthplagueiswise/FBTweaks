#import "FBTMCOverridesFile.h"
#import "FBTNativeMobileConfigOverrides.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static NSString *FBTMCAPIBundleID(void) {
    NSString *identifier = [NSBundle mainBundle].bundleIdentifier;
    return identifier.length ? identifier : @"unknown.bundle.id";
}

static NSArray<NSString *> *FBTMCAPISuiteCandidates(NSString *bundleID) {
    NSMutableOrderedSet<NSString *> *ids = [NSMutableOrderedSet orderedSet];
    NSString *lower = bundleID.lowercaseString;

    if ([lower isEqualToString:@"com.facebook.ota"]) {
        [ids addObject:@"group.facebook.ota"];
        [ids addObject:@"group.com.facebook.ota"];
    } else if ([lower isEqualToString:@"com.facebook.facebook"]) {
        [ids addObject:@"group.com.facebook.Facebook"];
        [ids addObject:@"group.facebook.Facebook"];
    }

    if (bundleID.length) [ids addObject:[@"group." stringByAppendingString:bundleID]];
    if ([bundleID hasPrefix:@"com."] && bundleID.length > 4) {
        [ids addObject:[@"group." stringByAppendingString:[bundleID substringFromIndex:4]]];
    }

    [ids addObject:@"group.com.facebook.Facebook"];
    [ids addObject:@"group.facebook.ota"];
    [ids addObject:@"group.com.facebook.ota"];
    [ids addObject:@"group.com.facebook.dogfood.internal"];
    [ids addObject:@"group.com.facebook.family"];
    return ids.array;
}

static void FBTMCAPIAddPath(NSMutableArray<NSString *> *paths, NSString *base, NSString *filename) {
    if (!base.length || !filename.length) return;
    NSString *candidate = [[[base stringByStandardizingPath] stringByAppendingPathComponent:filename] stringByStandardizingPath];
    if (![paths containsObject:candidate]) [paths addObject:candidate];
}

static NSArray<NSString *> *FBTMCAPICandidatePaths(NSString *bundleID, NSArray<NSString *> *suiteIDs, NSString *overridePath) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    NSArray<NSString *> *preferenceDirs = @[
        @"Library/Preferences",
        @"Preferences",
        @"AppData/Preferences",
        @"Documents/Preferences",
        @"AppData/Library/Preferences"
    ];
    for (NSString *relative in preferenceDirs) {
        NSString *dir = [home stringByAppendingPathComponent:relative];
        FBTMCAPIAddPath(paths, dir, [bundleID stringByAppendingPathExtension:@"plist"]);
        for (NSString *suite in suiteIDs) {
            FBTMCAPIAddPath(paths, dir, [suite stringByAppendingPathExtension:@"plist"]);
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *suite in suiteIDs) {
        NSURL *container = [fm containerURLForSecurityApplicationGroupIdentifier:suite];
        if (!container.path.length) continue;
        for (NSString *relative in @[@"Library/Preferences", @"Preferences", @"AppData/Preferences"]) {
            NSString *dir = [container.path stringByAppendingPathComponent:relative];
            FBTMCAPIAddPath(paths, dir, [suite stringByAppendingPathExtension:@"plist"]);
            FBTMCAPIAddPath(paths, dir, [bundleID stringByAppendingPathExtension:@"plist"]);
        }
        FBTMCAPIAddPath(paths, container.path, [suite stringByAppendingPathExtension:@"plist"]);
        FBTMCAPIAddPath(paths, container.path, [bundleID stringByAppendingPathExtension:@"plist"]);
    }

    // If the native override path is under AppGroup/Documents/mobileconfig,
    // the real app-group root is one level above Documents. In other builds
    // the mobileconfig directory can be directly under the group root.
    if (overridePath.length) {
        NSString *mobileConfigDir = [overridePath stringByDeletingLastPathComponent];
        NSString *parent = [mobileConfigDir stringByDeletingLastPathComponent];
        NSString *containerRoot = [parent.lastPathComponent isEqualToString:@"Documents"]
            ? [parent stringByDeletingLastPathComponent] : parent;
        for (NSString *root in @[parent ?: @"", containerRoot ?: @""]) {
            if (!root.length) continue;
            for (NSString *relative in @[@"Preferences", @"AppData/Preferences", @"Library/Preferences"]) {
                NSString *dir = [root stringByAppendingPathComponent:relative];
                FBTMCAPIAddPath(paths, dir, [bundleID stringByAppendingPathExtension:@"plist"]);
                for (NSString *suite in suiteIDs) {
                    FBTMCAPIAddPath(paths, dir, [suite stringByAppendingPathExtension:@"plist"]);
                }
            }
            for (NSString *suite in suiteIDs) {
                FBTMCAPIAddPath(paths, root, [suite stringByAppendingPathExtension:@"plist"]);
            }
        }
    }
    return paths;
}

static NSDictionary *FBTMCAPIReadPlist(NSString *path) {
    if (!path.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    NSError *error = nil;
    id value = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:&error];
    if (error || ![value isKindOfClass:[NSDictionary class]]) return nil;
    return value;
}

static NSDictionary *FBTMCAPISelectPlist(NSArray<NSString *> *paths,
                                          NSString *bundleID,
                                          NSArray<NSString *> *suiteIDs,
                                          NSString **selectedPath,
                                          NSUInteger *candidateCount) {
    NSDictionary *best = nil;
    NSString *bestPath = nil;
    NSInteger bestScore = NSIntegerMin;
    NSUInteger found = 0;
    for (NSString *path in paths) {
        NSDictionary *plist = FBTMCAPIReadPlist(path);
        if (!plist) continue;
        found++;
        NSDictionary *startup = [plist[@"FBMobileConfigStartupConfigs"] isKindOfClass:[NSDictionary class]]
            ? plist[@"FBMobileConfigStartupConfigs"] : nil;
        NSInteger score = startup ? (100000 + (NSInteger)startup.count * 10) : 0;
        NSString *filename = path.lastPathComponent.lowercaseString;
        if ([filename isEqualToString:[[bundleID stringByAppendingPathExtension:@"plist"] lowercaseString]]) score += 1200;
        for (NSString *suite in suiteIDs) {
            if ([filename isEqualToString:[[suite stringByAppendingPathExtension:@"plist"] lowercaseString]]) score += 2000;
            if ([path.lowercaseString containsString:suite.lowercaseString]) score += 100;
        }
        if ([path.lowercaseString containsString:bundleID.lowercaseString]) score += 300;
        if ([path.lowercaseString containsString:@"/preferences/"]) score += 50;
        if (score > bestScore) {
            bestScore = score;
            best = plist;
            bestPath = path;
        }
    }
    if (selectedPath) *selectedPath = bestPath;
    if (candidateCount) *candidateCount = found;
    return best;
}

static BOOL FBTMCAPIParseOverrideValue(NSString *raw, id effective, id *parsed) {
    NSString *value = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if ([effective isKindOfClass:[NSNumber class]]) {
        BOOL isBoolean = CFGetTypeID((__bridge CFTypeRef)effective) == CFBooleanGetTypeID();
        if (isBoolean) {
            NSString *lower = value.lowercaseString;
            if ([lower isEqualToString:@"true"] || [lower isEqualToString:@"yes"] || [lower isEqualToString:@"1"]) {
                if (parsed) *parsed = @YES;
                return YES;
            }
            if ([lower isEqualToString:@"false"] || [lower isEqualToString:@"no"] || [lower isEqualToString:@"0"]) {
                if (parsed) *parsed = @NO;
                return YES;
            }
            return NO;
        }
        NSScanner *scanner = [NSScanner scannerWithString:value];
        double number = 0;
        if (![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number)) return NO;
        if (parsed) *parsed = @(number);
        return YES;
    }
    if ([effective isKindOfClass:[NSString class]]) {
        if (parsed) *parsed = value;
        return YES;
    }
    if ([effective isKindOfClass:[NSArray class]] || [effective isKindOfClass:[NSDictionary class]]) {
        NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (!json) return NO;
        if (parsed) *parsed = json;
        return YES;
    }
    if ([effective isKindOfClass:[NSData class]]) {
        NSData *decoded = [[NSData alloc] initWithBase64EncodedString:value options:0];
        if (!decoded) return NO;
        if (parsed) *parsed = decoded;
        return YES;
    }
    if (parsed) *parsed = value;
    return YES;
}

static BOOL FBTMCAPIValuesEqual(id overrideValue, id effectiveValue) {
    if (!overrideValue || !effectiveValue) return NO;
    if ([overrideValue isKindOfClass:[NSNumber class]] && [effectiveValue isKindOfClass:[NSNumber class]]) {
        BOOL leftBoolean = CFGetTypeID((__bridge CFTypeRef)overrideValue) == CFBooleanGetTypeID();
        BOOL rightBoolean = CFGetTypeID((__bridge CFTypeRef)effectiveValue) == CFBooleanGetTypeID();
        if (leftBoolean != rightBoolean) return NO;
        return fabs([overrideValue doubleValue] - [effectiveValue doubleValue]) < 0.0000001;
    }
    return [overrideValue isEqual:effectiveValue];
}

static NSString *FBTMCAPIDisplayValue(id value) {
    if (!value || value == (id)kCFNull) return @"<sem valor>";
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return [value boolValue] ? @"true" : @"false";
        return [value stringValue];
    }
    if ([NSJSONSerialization isValidJSONObject:value]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
        NSString *text = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        return text ?: [value description];
    }
    return [value description] ?: @"";
}

static NSString *FBTMCAPIDateNow(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    });
    @synchronized (formatter) { return [formatter stringFromDate:[NSDate date]] ?: @""; }
}

@implementation FBTMCOverridesFile (EffectivePreferencesAudit)

+ (NSDictionary *)auditAgainstEffectivePreferences {
    NSString *bundleID = FBTMCAPIBundleID();
    NSArray<NSString *> *suiteIDs = FBTMCAPISuiteCandidates(bundleID);
    NSString *overridePath = FBTNativeMobileConfigOverridesFilePath();
    NSDictionary *overrides = nil;
    if (overridePath.length) {
        NSData *jsonData = [NSData dataWithContentsOfFile:overridePath];
        id jsonObject = jsonData.length ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
        if ([jsonObject isKindOfClass:[NSDictionary class]]) overrides = jsonObject;
    }

    NSArray<NSString *> *paths = FBTMCAPICandidatePaths(bundleID, suiteIDs, overridePath);
    NSString *preferencesPath = nil;
    NSUInteger plistCandidatesFound = 0;
    NSDictionary *preferences = FBTMCAPISelectPlist(paths, bundleID, suiteIDs, &preferencesPath, &plistCandidatesFound);
    NSDictionary *startupConfigs = [preferences[@"FBMobileConfigStartupConfigs"] isKindOfClass:[NSDictionary class]]
        ? preferences[@"FBMobileConfigStartupConfigs"] : nil;

    NSUInteger total = 0, matching = 0, mismatching = 0, absent = 0, noValue = 0, malformed = 0;
    NSMutableArray<NSDictionary *> *mismatchRows = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *absentRows = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *noValueRows = [NSMutableArray array];

    for (id rawConfigKey in overrides ?: @{}) {
        if (![rawConfigKey isKindOfClass:[NSString class]] || [rawConfigKey isEqualToString:@"_qe_overrides_"]) continue;
        id entries = overrides[rawConfigKey];
        if (![entries isKindOfClass:[NSArray class]]) continue;

        NSString *configKey = rawConfigKey;
        NSRange configColon = [configKey rangeOfString:@":"];
        NSString *configName = configColon.location == NSNotFound
            ? configKey
            : [[configKey substringFromIndex:NSMaxRange(configColon)]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        for (id rawEntry in (NSArray *)entries) {
            if (![rawEntry isKindOfClass:[NSString class]]) { malformed++; continue; }
            NSString *entry = rawEntry;
            NSRange firstColon = [entry rangeOfString:@":"];
            if (firstColon.location == NSNotFound) { malformed++; continue; }
            NSRange afterFirst = NSMakeRange(NSMaxRange(firstColon), entry.length - NSMaxRange(firstColon));
            NSRange secondRelative = [entry rangeOfString:@":" options:0 range:afterFirst];
            if (secondRelative.location == NSNotFound) { malformed++; continue; }

            NSString *indexText = [[entry substringToIndex:firstColon.location]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSScanner *indexScanner = [NSScanner scannerWithString:indexText];
            NSInteger index = -1;
            if (![indexScanner scanInteger:&index] || !indexScanner.isAtEnd || index < 0) { malformed++; continue; }

            NSString *param = [[entry substringWithRange:NSMakeRange(NSMaxRange(firstColon),
                secondRelative.location - NSMaxRange(firstColon))]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *overrideValue = [[entry substringFromIndex:NSMaxRange(secondRelative)]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!param.length) { malformed++; continue; }

            total++;
            NSString *plistKey = [NSString stringWithFormat:@"%@.%@", configName, param];
            id plistEntry = startupConfigs[plistKey];
            if (!plistEntry && preferences[plistKey]) plistEntry = preferences[plistKey];

            if (!plistEntry) {
                absent++;
                if (absentRows.count < 60) {
                    [absentRows addObject:@{
                        @"config_key": configKey, @"config": configName, @"index": @(index),
                        @"param": param, @"override_value": overrideValue, @"plist_key": plistKey,
                        @"status": @"not_represented_in_preferences_plist"
                    }];
                }
                continue;
            }

            id effectiveValue = [plistEntry isKindOfClass:[NSDictionary class]] ? plistEntry[@"v"] : plistEntry;
            if (!effectiveValue || effectiveValue == (id)kCFNull) {
                noValue++;
                if (noValueRows.count < 60) {
                    [noValueRows addObject:@{
                        @"config_key": configKey, @"config": configName, @"index": @(index),
                        @"param": param, @"override_value": overrideValue, @"plist_key": plistKey,
                        @"status": @"plist_entry_has_no_v_value"
                    }];
                }
                continue;
            }

            id parsedOverride = nil;
            BOOL parseOK = FBTMCAPIParseOverrideValue(overrideValue, effectiveValue, &parsedOverride);
            if (parseOK && FBTMCAPIValuesEqual(parsedOverride, effectiveValue)) {
                matching++;
            } else {
                mismatching++;
                if (mismatchRows.count < 250) {
                    [mismatchRows addObject:@{
                        @"config_key": configKey, @"config": configName, @"index": @(index),
                        @"param": param, @"override_value": overrideValue, @"plist_key": plistKey,
                        @"plist_value": FBTMCAPIDisplayValue(effectiveValue),
                        @"status": parseOK ? @"value_mismatch" : @"override_value_type_unparseable"
                    }];
                }
            }
        }
    }

    NSString *reportPath = overridePath.length
        ? [[overridePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"fbt_mc_overrides_plist_audit.json"]
        : nil;
    NSMutableDictionary *report = [@{
        @"schema_version": @1,
        @"generated_at_utc": FBTMCAPIDateNow(),
        @"bundle_id": bundleID,
        @"derived_preferences_suite_candidates": suiteIDs,
        @"override_file_path": overridePath ?: @"not_found",
        @"preferences_plist_path": preferencesPath ?: @"not_found",
        @"preferences_plist_candidates_found": @(plistCandidatesFound),
        @"startup_config_entries": @(startupConfigs.count),
        @"override_rows_total": @(total),
        @"values_matching_plist": @(matching),
        @"values_mismatching_plist": @(mismatching),
        @"parameters_not_represented_in_plist": @(absent),
        @"plist_entries_without_v": @(noValue),
        @"malformed_override_rows": @(malformed),
        @"mismatches_truncated": @(mismatching > mismatchRows.count),
        @"mismatches": mismatchRows,
        @"not_in_plist_sample": absentRows,
        @"plist_without_value_sample": noValueRows,
        @"interpretation": @"A mismatch means the override row and selected preferences plist disagree for the same config.param key. Parameters absent from FBMobileConfigStartupConfigs are not counted as mismatches and cannot be verified against this plist. This audits persisted preferences; it does not by itself prove that a runtime reader consumed the override."
    } mutableCopy];
    if (reportPath.length) report[@"audit_report_path"] = reportPath;

    if (reportPath.length) {
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
        if (data.length && !error) [data writeToFile:reportPath options:NSDataWritingAtomic error:nil];
        if (error) report[@"audit_write_error"] = error.localizedDescription ?: @"serialization_failed";
    } else {
        report[@"audit_write_error"] = @"mc_overrides_path_not_found";
    }
    return [report copy];
}

@end
