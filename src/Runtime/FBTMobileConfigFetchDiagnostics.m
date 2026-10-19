#import "FBTMobileConfigFetchDiagnostics.h"
#import "FBTNativeTrace.h"
#import "FBTNativeMobileConfigOverrides.h"
#import "FBTMobileConfigRuntime.h"
#import "FBTMobileConfigResponseCapture.h"
#import "FBTNamesResponseSummary.h"
#import "FBTMCOverridesFile.h"
#import "FBTMobileConfigDebugUIHooks.h"
#import "FBTFlagCatalog.h"
#import "FBTEmployeeDiagnostics.h"
#import "../FBTDefaults.h"
#import "FBTPrefix.h"
#import <pthread.h>

static pthread_mutex_t sDiagLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableArray<NSDictionary *> *sDiagEvents;
static NSDictionary *sDiagCacheState;
static NSMutableDictionary *sDiagInstallStates;
static const NSUInteger kFBTDiagEventLimit = 256;

static NSString *FBTDiagProcessSessionID(void) {
    static NSString *identifier;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ identifier = NSUUID.UUID.UUIDString; });
    return identifier;
}

static NSString *FBTDiagRedactText(NSString *input) {
    if (![input isKindOfClass:[NSString class]] || !input.length) return @"";
    NSString *text = FBTNamesRedactMessage(input);
    NSArray<NSString *> *patterns = @[
        @"(?i)\\b(authorization|cookie|set-cookie)\\s*:\\s*[^\\r\\n]*",
        @"(?i)\\b(authorization|cookie|set-cookie|access[_-]?token|session[_-]?key|password|secret|token)[\\s:=]+(?:bearer\\s+)?[^\\s,;]+",
        @"(?i)(https?://[^\\s?]+)\\?[^\\s]+"
    ];
    NSArray<NSString *> *replacements = @[@"$1: [REDACTED]", @"$1=[REDACTED]", @"$1?[REDACTED]"];
    for (NSUInteger i = 0; i < patterns.count; i++) {
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:patterns[i] options:0 error:&error];
        if (regex && !error) text = [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:replacements[i]];
    }
    if (text.length > 500) text = [[text substringToIndex:500] stringByAppendingString:@"…"];
    return text;
}

static NSString *FBTDiagMCStateLabel(FBTMCState state) {
    switch (state) {
        case FBTMCStateOff: return @"OFF";
        case FBTMCStateOn: return @"ON";
        case FBTMCStateSys:
        default: return @"SYS";
    }
}

static NSString *FBTDiagISODate(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    });
    @synchronized (formatter) {
        return [formatter stringFromDate:date ?: [NSDate date]] ?: @"";
    }
}

static NSUInteger FBTDiagStoreScore(NSURL *url) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger score = 0;
    for (NSString *relative in @[@"mobileconfig_qce", @"mobileconfig"]) {
        BOOL isQCE = [relative isEqualToString:@"mobileconfig_qce"];
        NSString *dir = [[url URLByAppendingPathComponent:relative isDirectory:YES] path];
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
            if (![name hasSuffix:@".data"]) continue;
            NSString *store = [dir stringByAppendingPathComponent:name];
            BOOL hasIndex = [fm fileExistsAtPath:[store stringByAppendingPathComponent:@"latest.idx"]];
            BOOL hasTable = [fm fileExistsAtPath:[store stringByAppendingPathComponent:@"0.mctable"]] ||
                            [fm fileExistsAtPath:[store stringByAppendingPathComponent:@"1.mctable"]] ||
                            [fm fileExistsAtPath:[store stringByAppendingPathComponent:@"2.mctable"]] ||
                            [fm fileExistsAtPath:[store stringByAppendingPathComponent:@"3.mctable"]];
            if (hasIndex || hasTable) score += isQCE ? 100 : 1;
        }
    }
    return score;
}

static NSURL *FBTDiagAppGroupURL(void) {
    NSString *nativePath = FBTNativeMobileConfigOverridesFilePath();
    if (nativePath.length && [[nativePath.lastPathComponent lowercaseString] isEqualToString:@"mc_overrides.json"]) {
        NSString *mobileConfigDir = [nativePath stringByDeletingLastPathComponent];
        NSString *containerDir = [mobileConfigDir stringByDeletingLastPathComponent];
        if (containerDir.length) {
            // This is the folder that contains sibling "mobileconfig" and
            // "mobileconfig_qce" stores. If nativePath is under Documents,
            // keep Documents as the diagnostics base instead of jumping to
            // the shared-container root.
            return [NSURL fileURLWithPath:containerDir isDirectory:YES];
        }
    }

    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";
    NSMutableOrderedSet<NSString *> *groups = [NSMutableOrderedSet orderedSet];
    if ([bundleID.lowercaseString isEqualToString:@"com.facebook.ota"]) {
        [groups addObject:@"group.facebook.ota"];
        [groups addObject:@"group.com.facebook.ota"];
    } else if ([bundleID.lowercaseString isEqualToString:@"com.facebook.facebook"]) {
        [groups addObject:@"group.com.facebook.Facebook"];
        [groups addObject:@"group.facebook.Facebook"];
    }
    if (bundleID.length) [groups addObject:[@"group." stringByAppendingString:bundleID]];
    if ([bundleID hasPrefix:@"com."] && bundleID.length > 4) {
        [groups addObject:[@"group." stringByAppendingString:[bundleID substringFromIndex:4]]];
    }
    [groups addObjectsFromArray:@[
        @"group.com.facebook.Facebook",
        @"group.facebook.ota",
        @"group.com.facebook.ota",
        @"group.com.facebook.dogfood.internal",
        @"group.com.facebook.family"
    ]];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *group in groups) {
        NSURL *url = [fm containerURLForSecurityApplicationGroupIdentifier:group];
        if (!url.path.length) continue;
        BOOL hasDocumentsMC = [fm fileExistsAtPath:[url.path stringByAppendingPathComponent:@"Documents/mobileconfig"]];
        BOOL hasRootMC = [fm fileExistsAtPath:[url.path stringByAppendingPathComponent:@"mobileconfig"]];
        BOOL hasDocumentsQCE = [fm fileExistsAtPath:[url.path stringByAppendingPathComponent:@"Documents/mobileconfig_qce"]];
        BOOL hasRootQCE = [fm fileExistsAtPath:[url.path stringByAppendingPathComponent:@"mobileconfig_qce"]];
        if (hasDocumentsMC || hasDocumentsQCE) {
            return [url URLByAppendingPathComponent:@"Documents" isDirectory:YES];
        }
        if (hasRootMC || hasRootQCE) return url;
    }
    return nil;
}

static NSString *FBTDiagFilePath(void) {
    NSString *nativePath = FBTNativeMobileConfigOverridesFilePath();
    if (nativePath.length && [[nativePath.lastPathComponent lowercaseString] isEqualToString:@"mc_overrides.json"]) {
        return [[nativePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"fbt_fetch_diagnostics.json"];
    }
    NSURL *group = FBTDiagAppGroupURL();
    if (!group.path.length) return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/FBTweak/mobileconfig/fbt_fetch_diagnostics.json"];
    return [[[group URLByAppendingPathComponent:@"mobileconfig"] URLByAppendingPathComponent:@"fbt_fetch_diagnostics.json"] path];
}

static NSDictionary *FBTDiagSafeEvent(NSString *event, NSDictionary *details) {
    NSSet *allowed = [NSSet setWithArray:@[@"body_status", @"decoded_response_bytes", @"id_to_names_valid", @"id_to_names_count", @"server_error_code", @"server_error_subcode", @"server_error_type", @"server_error_message", @"matched_ui_query_count", @"native_tigon_correlation", @"request_id", @"request_param_count", @"routing_hint_present", @"payload_provenance", @"request_metadata_source", @"request_parameter_summary", @"simple_callback_hooks_installed", @"native_transport_success", @"bool_reader_available", @"int64_reader_available", @"double_reader_available", @"string_reader_available", @"param", @"config", @"key", @"backend_type", @"backend", @"alert", @"alert_message", @"retry", @"context_count", @"arg2", @"arg3", @"fetch_result", @"duration_ms", @"hook_installed", @"error_domain", @"error_code", @"rebind_status", @"http_status", @"message", @"force", @"download_success", @"output_universe_nonempty", @"output_gk_nonempty", @"metamap_argument_present", @"capture_reason", @"capture_window_seconds", @"capture_surface", @"hooked_session_class_count", @"body_capture_status", @"payload_file", @"payload_sha256", @"response_bytes", @"legacy_refresh_override_file_state", @"builtin_query_hash_override_file_state", @"content_type", @"request_host", @"request_path", @"request_method", @"request_body_bytes", @"query_hash_state", @"query_hash_length", @"one_query_hash_state", @"one_query_hash_length", @"capture_enabled", @"network_error_domain", @"network_error_code", @"response_body_bytes", @"armed", @"last_capture_status", @"last_payload_file", @"captured_body_count", @"surface", @"transport", @"query_hash_source", @"http_status_source", @"error_object_present", @"request_body_persisted", @"tigon_body_hook_installed", @"tigon_request_hook_installed", @"tigon_response_hook_installed", @"tigon_eom_hook_installed", @"tigon_error_hook_installed", @"request_url_getter_available", @"request_method_getter_available", @"url_components_available", @"tigon_rebind_status", @"tigon_callback", @"tigon_response_bytes", @"body_chunk_bytes", @"tigon_completed_response_count", @"tigon_context_count"]];
    NSMutableDictionary *safe = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"experiment_id", @"experiment_profile", @"experiment_state", @"employee_field_added",
        @"authorization_state", @"authorization_scheme", @"authorization_credential_present", @"authorization_observation_stage",
        @"identity_read_sequence_at_start", @"identity_read_sequence_at_completion", @"local_employee_enabled", @"tw_probe_armed_at_start"]) {
        id value = details[key];
        if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) safe[key] = value;
    }
    // Both fields are produced from fixed-key, credential-free native probes.
    for (NSString *key in @[@"tigon_service_snapshot", @"auth_validation_read_snapshot"]) {
        if ([details[key] isKindOfClass:NSString.class]) safe[key] = details[key];
    }
    for (NSString *key in allowed) {
        id value = details[key];
        if (!value || value == (id)kCFNull) continue;
        if (([key isEqualToString:@"server_error_message"] || [key isEqualToString:@"server_error_type"] || [key isEqualToString:@"backend"] || [key isEqualToString:@"alert"] || [key isEqualToString:@"alert_message"] || [key isEqualToString:@"arg2"] || [key isEqualToString:@"arg3"] || [key isEqualToString:@"error_domain"] || [key isEqualToString:@"message"]) && [value isKindOfClass:[NSString class]]) {
            // Backend labels can contain numeric account/admin identifiers.
            NSString *label = FBTDiagRedactText(value);
            NSError *error = nil;
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?<![0-9])[0-9]{6,}(?![0-9])" options:0 error:&error];
            if (regex && !error) label = [regex stringByReplacingMatchesInString:label options:0 range:NSMakeRange(0, label.length) withTemplate:@"[redacted-id]"];
            value = label;
        }
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) safe[key] = value;
    }
    BOOL annotateQEFlags = [event isEqualToString:@"qe_info_request_started"] ||
                           [event isEqualToString:@"qe_info_request_returned"] ||
                           [event isEqualToString:@"name_download_started"] ||
                           [event isEqualToString:@"name_download_completed"];
    if (annotateQEFlags) {
        // These are the tri-state values currently written in mc_overrides.json,
        // not proof the running binary resolved or consumed either flag.
        FBTMCState legacyState = [FBTMCOverridesFile stateForConfig:@"84491:mobile_config_internal_settings_features" paramIdx:2];
        FBTMCState hashState = [FBTMCOverridesFile stateForConfig:@"4626:mobileconfig_session" paramIdx:4];
        safe[@"legacy_refresh_override_file_state"] = FBTDiagMCStateLabel(legacyState);
        safe[@"builtin_query_hash_override_file_state"] = FBTDiagMCStateLabel(hashState);
    }
    safe[@"process_session_id"] = FBTDiagProcessSessionID();
    safe[@"event"] = event ?: @"unknown";
    safe[@"time_utc"] = FBTDiagISODate([NSDate date]);
    return [safe copy];
}

static NSDictionary *FBTDiagLoadExisting(void) {
    NSString *path = FBTDiagFilePath();
    NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data.length) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSDictionary *FBTDiagStoreSummary(NSURL *base, NSString *relativePath, NSString *label) {
    NSURL *dir = [base URLByAppendingPathComponent:relativePath isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir.path error:nil] ?: @[];
    NSMutableArray *stores = [NSMutableArray array];
    for (NSString *name in names) {
        if (![name hasSuffix:@".data"] && ![name isEqualToString:@"sessionless.data"] && ![name hasSuffix:@"_pt_BR_V1.data"]) continue;
        NSURL *store = [dir URLByAppendingPathComponent:name isDirectory:YES];
        NSString *idxPath = [[store URLByAppendingPathComponent:@"latest.idx"] path];
        NSString *idx = [[NSString stringWithContentsOfFile:idxPath encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *namesFile = nil;
        for (NSString *candidate in @[@"params_names_v4_u0.txt", @"params_names_v4_u3.txt", @"params_names_v4_u4.txt"]) {
            NSString *candidatePath = [[store URLByAppendingPathComponent:candidate] path];
            if ([fm fileExistsAtPath:candidatePath]) { namesFile = candidatePath; break; }
        }
        NSNumber *nameCount = nil;
        if (namesFile) {
            NSData *namesData = [NSData dataWithContentsOfFile:namesFile];
            id parsed = namesData.length ? [NSJSONSerialization JSONObjectWithData:namesData options:0 error:nil] : nil;
            if ([parsed isKindOfClass:[NSArray class]]) nameCount = @([(NSArray *)parsed count]);
        }
        NSDate *newest = nil;
        unsigned long long bytes = 0;
        for (NSString *file in @[@"latest.idx", @"0.meta", @"1.meta", @"2.meta", @"3.meta", @"0.mctable", @"1.mctable", @"2.mctable", @"3.mctable"]) {
            NSString *p = [[store URLByAppendingPathComponent:file] path];
            NSDictionary *attrs = [fm attributesOfItemAtPath:p error:nil];
            NSDate *modified = attrs[NSFileModificationDate];
            if (modified && (!newest || [modified compare:newest] == NSOrderedDescending)) newest = modified;
            bytes += [attrs[NSFileSize] unsignedLongLongValue];
        }
        NSMutableDictionary *entry = [@{@"store": name, @"latest_generation": idx.length ? idx : @"missing", @"known_file_bytes": @(bytes)} mutableCopy];
        if (nameCount) entry[@"param_name_count"] = nameCount;
        if (newest) entry[@"latest_file_utc"] = FBTDiagISODate(newest);
        [stores addObject:entry];
    }
    return @{@"kind": label, @"stores": stores};
}

static NSDictionary *FBTDiagResponseDumpSummary(NSURL *base) {
    NSURL *dir = [base URLByAppendingPathComponent:@"mobileconfig" isDirectory:YES];
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir.path error:nil] ?: @[];
    NSMutableArray *dumps = [NSMutableArray array];
    for (NSString *name in names) {
        if (![name hasPrefix:@"mc_sync_response_dump"] || ![name hasSuffix:@".json"]) continue;
        NSString *path = [[dir URLByAppendingPathComponent:name] path];
        NSData *data = [NSData dataWithContentsOfFile:path];
        id obj = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *dump = obj;
        id configs = dump[@"configs"];
        NSUInteger count = [configs respondsToSelector:@selector(count)] ? [configs count] : 0;
        NSDictionary *extra = [dump[@"extra"] isKindOfClass:[NSDictionary class]] ? dump[@"extra"] : @{};
        id qceRaw = extra[@"qce"];
        NSUInteger qceCount = 0;
        if ([qceRaw isKindOfClass:[NSString class]]) {
            NSData *qceData = [qceRaw dataUsingEncoding:NSUTF8StringEncoding];
            id qce = qceData.length ? [NSJSONSerialization JSONObjectWithData:qceData options:0 error:nil] : nil;
            qceCount = [qce respondsToSelector:@selector(count)] ? [qce count] : 0;
        } else if ([qceRaw respondsToSelector:@selector(count)]) {
            qceCount = [qceRaw count];
        }
        [dumps addObject:@{
            @"dump": name,
            @"timestamp": [dump[@"ts"] respondsToSelector:@selector(stringValue)] ? [dump[@"ts"] stringValue] : @"unknown",
            @"config_count": @(count),
            @"has_query_hash": @([dump[@"query_hash"] isKindOfClass:[NSString class]] && [dump[@"query_hash"] length] > 0),
            @"qce_entry_count": @(qceCount)
        }];
    }
    return @{@"response_dumps": dumps};
}

static NSDictionary *FBTDiagCacheSummary(void) {
    NSURL *base = FBTDiagAppGroupURL();
    if (!base) return @{@"app_group_available": @NO};
    NSDictionary *qce = FBTDiagStoreSummary(base, @"mobileconfig_qce", @"qce_metadata");
    NSDictionary *main = FBTDiagStoreSummary(base, @"mobileconfig", @"mobileconfig_values");
    NSDictionary *dumps = FBTDiagResponseDumpSummary(base);
    return @{@"app_group_available": @YES,
             @"qce_metadata": qce[@"stores"] ?: @[],
             @"mobileconfig_value_stores": main[@"stores"] ?: @[],
             @"response_dumps": dumps[@"response_dumps"] ?: @[]};
}

static NSDictionary *FBTDiagSessionSettings(void) {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    NSBundle *host = NSBundle.mainBundle;
    settings[@"host_app"] = @{@"bundle_id": host.bundleIdentifier ?: @"unknown",
        @"version": [host objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"build": [host objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown"};
    for (NSString *key in @[FBTKeyMasterEnabled, FBTKeyMobileConfigRuntimeEnabled,
            FBTKeyMobileConfigNativeUIWarmupEnabled, FBTKeyMobileConfigCaptureEnabled,
            FBTKeyMobileConfigOverridesEnabled, FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        settings[key] = @([[NSUserDefaults standardUserDefaults] boolForKey:key]);
    }
    NSURL *info = [FBTFlagCatalog bundleURLForResource:@"FBTBuildInfo" extension:@"json"];
    NSData *data = info ? [NSData dataWithContentsOfURL:info] : nil;
    id build = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([build isKindOfClass:[NSDictionary class]]) settings[@"build"] = build;
    return settings;
}

void FBTMobileConfigFetchDiagnosticsRecord(NSString *event, NSDictionary *details) {
    BOOL fullLogEnabled = [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
    if (!fullLogEnabled && !FBTNativeTraceIsEnabled()) return;
    NSDictionary *safeEvent = FBTDiagSafeEvent(event, details ?: @{});
    FBTNativeTraceRecordNetwork(event, safeEvent);
    if (!fullLogEnabled) return;
    pthread_mutex_lock(&sDiagLock);
    if (!sDiagEvents) {
        NSDictionary *existing = FBTDiagLoadExisting();
        NSArray *events = [existing[@"events"] isKindOfClass:[NSArray class]] ? existing[@"events"] : @[];
        sDiagEvents = [events mutableCopy];
        sDiagCacheState = [existing[@"cache_state"] isKindOfClass:[NSDictionary class]] ? existing[@"cache_state"] : nil;
    }
    BOOL installEvent = [event hasSuffix:@"_hook"] || [event hasSuffix:@"_hooks"];
    if (installEvent) {
        NSMutableDictionary *state = [safeEvent mutableCopy];
        [state removeObjectForKey:@"time_utc"];
        if (!sDiagInstallStates) sDiagInstallStates = [NSMutableDictionary dictionary];
        if ([sDiagInstallStates[event] isEqual:state]) {
            pthread_mutex_unlock(&sDiagLock);
            return;
        }
        sDiagInstallStates[event] = [state copy];
    }
    [sDiagEvents addObject:safeEvent];
    if (sDiagEvents.count > kFBTDiagEventLimit) {
        [sDiagEvents removeObjectsInRange:NSMakeRange(0, sDiagEvents.count - kFBTDiagEventLimit)];
    }
    BOOL refreshCache = [event isEqualToString:@"capture_started"] ||
                        [event isEqualToString:@"qe_info_request_returned"] ||
                        [event isEqualToString:@"name_download_completed"] ||
                        [event isEqualToString:@"network_response_body_captured"] ||
                        [event isEqualToString:@"network_response_body_skipped"];
    if (!sDiagCacheState || refreshCache) sDiagCacheState = FBTDiagCacheSummary();
    NSDictionary *report = @{ @"schema_version": @7,
                             @"employee_identity": FBTEmployeeDiagnosticsSnapshot(),
                             @"process_session_id": FBTDiagProcessSessionID(),
                             @"updated_at_utc": FBTDiagISODate([NSDate date]),
                             @"events": [sDiagEvents copy],
                             @"names_assessments": FBTNamesAssessHistory(sDiagEvents, FBTDiagProcessSessionID()),
                             @"capture_enabled": @([FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled] && ![event isEqualToString:@"capture_paused"]),
                             @"cache_state": sDiagCacheState ?: @{},
                             @"runtime": FBTMobileConfigRuntimeStatus(),
                             @"transport": FBTMobileConfigResponseCaptureStatus(),
                             @"native_hooks": FBTMobileConfigDebugUIHookStatus(),
                             @"session_settings": FBTDiagSessionSettings() };
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path = FBTDiagFilePath();
    if (path.length && json.length) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        [json writeToFile:path options:NSDataWritingAtomic error:nil];
    } else {
        FBTLog(@"MC fetch diagnostics not persisted: App Group container unavailable");
    }
    pthread_mutex_unlock(&sDiagLock);
    FBTLog(@"MC fetch diagnostic event=%@ persisted=%d", safeEvent[@"event"], path.length > 0);
}

NSDictionary *FBTMobileConfigFetchDiagnosticsSnapshot(void) {
    pthread_mutex_lock(&sDiagLock);
    NSDictionary *existing = FBTDiagLoadExisting();
    NSArray *events = sDiagEvents ? [sDiagEvents copy] : ([existing[@"events"] isKindOfClass:[NSArray class]] ? existing[@"events"] : @[]);
    NSMutableDictionary *report = [NSMutableDictionary dictionaryWithDictionary:existing ?: @{}];
    report[@"events"] = events;
    report[@"schema_version"] = @7;
    report[@"employee_identity"] = FBTEmployeeDiagnosticsSnapshot();
    report[@"names_assessments"] = FBTNamesAssessHistory(events, FBTDiagProcessSessionID());
    report[@"capture_enabled"] = @([FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]);
    report[@"cache_state"] = FBTDiagCacheSummary();
    report[@"process_session_id"] = FBTDiagProcessSessionID();
    report[@"native_hooks"] = FBTMobileConfigDebugUIHookStatus();
    report[@"session_settings"] = FBTDiagSessionSettings();
    report[@"runtime"] = FBTMobileConfigRuntimeStatus();
    report[@"transport"] = FBTMobileConfigResponseCaptureStatus();
    report[@"updated_at_utc"] = FBTDiagISODate([NSDate date]);
    pthread_mutex_unlock(&sDiagLock);
    return [report copy];
}

NSString *FBTMobileConfigFetchDiagnosticsJSON(void) {
    NSDictionary *snapshot = FBTMobileConfigFetchDiagnosticsSnapshot();
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
    return data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{\n  \"error\": \"diagnostics unavailable\"\n}";
}

void FBTMobileConfigFetchDiagnosticsReset(void) {
    pthread_mutex_lock(&sDiagLock);
    sDiagEvents = [NSMutableArray array];
    sDiagCacheState = nil;
    pthread_mutex_unlock(&sDiagLock);
    FBTMobileConfigFetchDiagnosticsRecord(@"capture_started", @{});
}




