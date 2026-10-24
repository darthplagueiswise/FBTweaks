#import "FBTNetworkInspectorStore.h"
#import <CommonCrypto/CommonDigest.h>
#import <stdatomic.h>
#import <TargetConditionals.h>

static atomic_bool sCapturing = ATOMIC_VAR_INIT(false);
static dispatch_queue_t sQueue;
static NSString *sProcessTag;
static NSMutableDictionary<NSString *, NSMutableDictionary *> *sLive;
static const NSUInteger kMaxRecords = 60;
static const NSUInteger kMaxRequestBytes = 1024 * 1024;
static const NSUInteger kMaxResponseBytes = 2 * 1024 * 1024;

static void FBTNIInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sQueue = dispatch_queue_create("com.fbtweak.networkinspector.storage", DISPATCH_QUEUE_SERIAL);
        sProcessTag = [NSUUID.UUID.UUIDString copy];
        sLive = [NSMutableDictionary dictionary];
    });
}
static NSString *FBTNIRoot(void) {
    NSString *app = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    if (!app) app = NSHomeDirectory();
    return [[app stringByAppendingPathComponent:@"FBTweak"] stringByAppendingPathComponent:@"NetworkInspector"];
}
static void FBTNIPrepareDirectory(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *root = FBTNIRoot();
    [manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
#if TARGET_OS_IPHONE
    [manager setAttributes:@{NSFileProtectionKey: NSFileProtectionComplete} ofItemAtPath:root error:nil];
#endif
}
static NSString *FBTNIRecordKey(NSNumber *requestID) {
    if (![requestID isKindOfClass:NSNumber.class]) return nil;
    return [NSString stringWithFormat:@"%@-%@", sProcessTag, requestID];
}
static NSString *FBTNIFile(NSString *recordID) {
    if (![recordID isKindOfClass:NSString.class] || !recordID.length ||
        [recordID rangeOfString:@"/"].location != NSNotFound ||
        [recordID rangeOfString:@".."].location != NSNotFound) return nil;
    return [FBTNIRoot() stringByAppendingPathComponent:[recordID stringByAppendingString:@".json"]];
}
static NSString *FBTNIHash(NSData *bytes) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}
static NSString *FBTNINow(void) {
    return [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]];
}
static NSMutableDictionary *FBTNIEntry(NSNumber *requestID) {
    NSString *identifier = FBTNIRecordKey(requestID);
    if (!identifier) return nil;
    NSMutableDictionary *value = sLive[identifier];
    if (!value) {
        value = [@{@"record_id": identifier, @"request_id": requestID,
                   @"capture_session": sProcessTag, @"created_at": FBTNINow(),
                   @"capture_provenance": @"FBSharedFramework UUID-verified native MobileConfig hooks"} mutableCopy];
        sLive[identifier] = value;
    }
    return value;
}
static NSDictionary *FBTNIEncodedBody(NSData *bytes, NSUInteger maxSize) {
    if (![bytes isKindOfClass:NSData.class]) return @{@"capture_status": @"not_observed"};
    if (bytes.length > maxSize)
        return @{@"capture_status": @"over_capture_limit", @"length": @(bytes.length)};
    NSMutableDictionary *result = [@{@"capture_status": @"complete", @"length": @(bytes.length),
        @"sha256": FBTNIHash(bytes), @"base64": [bytes base64EncodedStringWithOptions:0] ?: @""} mutableCopy];
    // Preview only; the Base64 above holds the exact bytes, including non-UTF8.
    NSUInteger previewLength = MIN(bytes.length, (NSUInteger)16384);
    NSData *first = [bytes subdataWithRange:NSMakeRange(0, previewLength)];
    NSString *preview = [[NSString alloc] initWithData:first encoding:NSUTF8StringEncoding];
    if (preview) result[@"utf8_preview"] = preview;
    return result;
}
static void FBTNIPrune(void) {
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:FBTNIRoot() error:nil] ?: @[];
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    for (NSString *name in names) {
        if (![name hasSuffix:@".json"]) continue;
        NSString *path = [FBTNIRoot() stringByAppendingPathComponent:name];
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] ?: @{};
        [candidates addObject:@{@"name": name, @"date": attrs[NSFileModificationDate] ?: [NSDate distantPast]}];
    }
    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date"] compare:a[@"date"]];
    }];
    for (NSUInteger i = kMaxRecords; i < candidates.count; i++) {
        NSString *name = candidates[i][@"name"];
        [NSFileManager.defaultManager removeItemAtPath:[FBTNIRoot() stringByAppendingPathComponent:name] error:nil];
        [sLive removeObjectForKey:[name stringByDeletingPathExtension]];
    }
}
static void FBTNIPersist(NSMutableDictionary *record) {
    FBTNIPrepareDirectory();
    record[@"updated_at"] = FBTNINow();
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path = FBTNIFile(record[@"record_id"]);
    if (!json.length || !path) return;
#if TARGET_OS_IPHONE
    NSDataWritingOptions flags = NSDataWritingAtomic | NSDataWritingFileProtectionComplete;
#else
    NSDataWritingOptions flags = NSDataWritingAtomic;
#endif
    if ([json writeToFile:path options:flags error:nil]) {
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:nil];
    }
    FBTNIPrune();
}
static void FBTNIUpdate(NSNumber *requestID, void (^updates)(NSMutableDictionary *)) {
    if (!atomic_load_explicit(&sCapturing, memory_order_acquire)) return;
    FBTNIInit();
    if (!requestID || !updates) return;
    dispatch_async(sQueue, ^{
        NSMutableDictionary *record = FBTNIEntry(requestID);
        if (!record) return;
        updates(record);
        FBTNIPersist(record);
    });
}
BOOL FBTNetworkInspectorIsCapturing(void) {
    return atomic_load_explicit(&sCapturing, memory_order_acquire);
}
void FBTNetworkInspectorSetCapturing(BOOL enabled) {
    FBTNIInit();
    atomic_store_explicit(&sCapturing, enabled, memory_order_release);
}
void FBTNetworkInspectorRecordRequest(NSDictionary *request, NSArray<NSDictionary *> *pairs) {
    if (!FBTNetworkInspectorIsCapturing()) return;
    NSNumber *rid = request[@"request_id"];
    NSMutableArray *bounded = [NSMutableArray array];
    NSUInteger bytes = 0;
    for (NSDictionary *pair in pairs) {
        NSString *name = [pair[@"name"] isKindOfClass:NSString.class] ? pair[@"name"] : @"";
        NSString *value = [pair[@"value"] isKindOfClass:NSString.class] ? pair[@"value"] : @"";
        bytes += [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (bytes > kMaxRequestBytes) break;
        [bounded addObject:@{@"name": name, @"value": value}];
    }
    NSArray *copyPairs = [bounded copy];
    NSDictionary *copy = [request copy];
    FBTNIUpdate(rid, ^(NSMutableDictionary *record) {
        record[@"stage"] = @"request_started";
        record[@"purpose"] = copy[@"capture_reason"] ?: @"unknown";
        record[@"method"] = copy[@"request_method"] ?: @"unknown";
        record[@"transport"] = @"FBMobileConfigTigonFetcher";
        record[@"request_parameter_pairs"] = copyPairs;
        record[@"request_parameter_capture"] = (bytes > kMaxRequestBytes || [copy[@"inspector_request_truncated"] boolValue]) ? @"truncated_at_1mb" : @"complete";
        record[@"request_parameter_total_count"] = copy[@"request_param_count"] ?: @(copyPairs.count);
        record[@"request_parameter_captured_count"] = @(copyPairs.count);
        record[@"routing_hint"] = copy[@"inspector_routing_hint"] ?: @"";
        record[@"stack_target_word"] = copy[@"inspector_target"] ?: @"not_observed";
        record[@"tigon_service_snapshot"] = copy[@"tigon_service_snapshot"] ?: @"{}";
        record[@"request_source"] = @"asyncFetch_parameters_before_Tigon_request_builder";
    });
}
void FBTNetworkInspectorRecordTigon(NSDictionary *context, NSData *body) {
    if (!FBTNetworkInspectorIsCapturing()) return;
    NSNumber *rid = context[@"request_id"];
    NSDictionary *copy = [context copy];
    NSString *bodyState = [context[@"body_capture_status"] isKindOfClass:NSString.class]
        ? context[@"body_capture_status"] : (body.length ? @"ready" : @"not_delivered_to_observed_callback");
    NSDictionary *encoded = [bodyState isEqualToString:@"ready"]
        ? FBTNIEncodedBody(body, kMaxResponseBytes)
        : @{@"capture_status": bodyState, @"length": @(body.length)};
    FBTNIUpdate(rid, ^(NSMutableDictionary *record) {
        if (!record[@"purpose"]) record[@"purpose"] = copy[@"capture_reason"] ?: @"tigon_unclassified";
        if (!record[@"stage"]) record[@"stage"] = @"tigon_response_received";
        record[@"tigon_http_status"] = copy[@"http_status"] ?: @0;
        record[@"tigon_status_source"] = copy[@"http_status_source"] ?: @"not_observed";
        for (NSString *field in @[@"request_host", @"request_path", @"request_method", @"authorization_state",
                                   @"authorization_scheme", @"authorization_credential_present", @"payload_provenance"]) {
            if (copy[field]) record[field] = copy[field];
        }
        for (NSString *field in @[@"inspector_raw_host", @"inspector_raw_path", @"inspector_query"]) {
            if (copy[field]) record[field] = copy[field];
        }
        if ([copy[@"inspector_headers"] isKindOfClass:NSDictionary.class])
            record[@"known_request_headers"] = copy[@"inspector_headers"];
        record[@"http_headers_source"] = @"TigonRequest.findHeader_known_names_only";
        record[@"native_tigon_correlation"] = copy[@"native_tigon_correlation"] ?: @"";
        record[@"http_response_body"] = encoded;
        record[@"http_response_source"] = copy[@"payload_provenance"] ?: @"TigonSimpleCallbacks";
    });
}
void FBTNetworkInspectorRecordCompletion(NSDictionary *completion, NSData *body) {
    if (!FBTNetworkInspectorIsCapturing()) return;
    NSDictionary *copy = [completion copy];
    NSDictionary *encoded = FBTNIEncodedBody(body, kMaxResponseBytes);
    FBTNIUpdate(copy[@"request_id"], ^(NSMutableDictionary *record) {
        record[@"stage"] = @"native_completion";
        record[@"native_transport_success"] = copy[@"native_transport_success"] ?: @NO;
        record[@"native_completion_status"] = copy[@"http_status"] ?: @0;
        record[@"native_completion_status_source"] = copy[@"http_status_source"] ?: @"not_observed";
        record[@"duration_ms"] = copy[@"duration_ms"] ?: @0;
        record[@"native_completion_body"] = encoded;
        record[@"native_body_source"] = copy[@"payload_provenance"] ?: @"native_decoded_completion";
        record[@"note"] = @"HTTP body, when observed, comes from TigonSimpleCallbacks; native error text is a separate field.";
    });
}
NSArray<NSDictionary *> *FBTNetworkInspectorSummaries(void) {
    FBTNIInit();
    __block NSArray *result = @[];
    dispatch_sync(sQueue, ^{
        NSMutableArray *items = [NSMutableArray array];
        NSArray *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:FBTNIRoot() error:nil] ?: @[];
        for (NSString *name in names) {
            if (![name hasSuffix:@".json"]) continue;
            NSData *data = [NSData dataWithContentsOfFile:[FBTNIRoot() stringByAppendingPathComponent:name]];
            NSDictionary *record = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (![record isKindOfClass:NSDictionary.class]) continue;
            [items addObject:@{@"record_id": record[@"record_id"] ?: @"",
                @"created_at": record[@"created_at"] ?: @"",
                @"purpose": record[@"purpose"] ?: @"unknown",
                @"http_status": [record[@"tigon_http_status"] integerValue] >= 100
                    ? record[@"tigon_http_status"] : (record[@"native_completion_status"] ?: @0),
                @"stage": record[@"stage"] ?: @"unknown",
                @"request_id": record[@"request_id"] ?: @0}];
        }
        [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"created_at"] compare:a[@"created_at"]];
        }];
        result = [items copy];
    });
    return result;
}
NSDictionary *FBTNetworkInspectorRecordWithID(NSString *recordID) {
    FBTNIInit();
    __block NSDictionary *result;
    dispatch_sync(sQueue, ^{
        NSString *path = FBTNIFile(recordID);
        NSData *bytes = path ? [NSData dataWithContentsOfFile:path] : nil;
        id object = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
        result = [object isKindOfClass:NSDictionary.class] ? object : @{};
    });
    return result ?: @{};
}
NSArray<NSURL *> *FBTNetworkInspectorExportURLs(void) {
    FBTNIInit();
    __block NSArray *result;
    dispatch_sync(sQueue, ^{
        NSMutableArray *urls = [NSMutableArray array];
        NSArray *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:FBTNIRoot() error:nil] ?: @[];
        for (NSString *name in names)
            if ([name hasSuffix:@".json"]) [urls addObject:[NSURL fileURLWithPath:[FBTNIRoot() stringByAppendingPathComponent:name]]];
        result = [urls copy];
    });
    return result ?: @[];
}
void FBTNetworkInspectorClear(void) {
    FBTNIInit();
    dispatch_sync(sQueue, ^{
        [sLive removeAllObjects];
        NSString *root = FBTNIRoot();
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil] ?: @[])
            if ([name hasSuffix:@".json"])
                [NSFileManager.defaultManager removeItemAtPath:[root stringByAppendingPathComponent:name] error:nil];
    });
}
NSDictionary *FBTNetworkInspectorStatus(void) {
    NSArray *records = FBTNetworkInspectorSummaries();
    return @{@"capturing": @(FBTNetworkInspectorIsCapturing()), @"records": @(records.count),
             @"storage_location": @"Application Support/FBTweak/NetworkInspector",
             @"max_records": @(kMaxRecords), @"max_request_bytes": @(kMaxRequestBytes),
             @"max_http_body_bytes": @(kMaxResponseBytes)};
}
