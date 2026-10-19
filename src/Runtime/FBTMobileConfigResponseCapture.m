#import "FBTMobileConfigResponseCapture.h"
#import "FBTMobileConfigFetchDiagnostics.h"
#import "FBTNamesResponseSummary.h"
#import "FBTNativeMobileConfigOverrides.h"
#import "../FBTDefaults.h"
#import "../FBTPrefix.h"
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>

static NSMutableDictionary<NSString *, NSValue *> *sOriginalSessionImpByClass;
static NSMutableSet<NSString *> *sHookedSessionClasses;
static NSLock *sCaptureLock;
static BOOL sCaptureHookInstalled = NO;
static CFTimeInterval sCaptureArmedUntil = 0;
static NSString *sCaptureReason = nil;
static NSString *sLastBodyPath = nil;
static NSString *sLastBodyRelativePath = nil;
static NSString *sLastCaptureStatus = @"not_armed";
static NSUInteger sCapturedBodyCount = 0;

typedef NSURLSessionDataTask *(*FBTSessionDataTaskOrig)(
    id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));

static NSString *FBTResponseCaptureBasePath(void) {
    NSString *nativePath = FBTNativeMobileConfigOverridesFilePath();
    if (nativePath.length &&
        [[nativePath.lastPathComponent lowercaseString] isEqualToString:@"mc_overrides.json"]) {
        NSString *mobileConfigDir = [nativePath stringByDeletingLastPathComponent];
        NSString *container = [mobileConfigDir stringByDeletingLastPathComponent];
        if (container.length) return [container stringByAppendingPathComponent:@"mobileconfig/fbt_fetch_payloads"];
    }
    NSArray<NSString *> *groups = @[
        @"group.com.facebook.dogfood.internal",
        @"group.com.facebook.Facebook",
        @"group.com.facebook.family"
    ];
    for (NSString *group in groups) {
        NSURL *url = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:group];
        if (url.path.length) {
            return [[url URLByAppendingPathComponent:@"mobileconfig/fbt_fetch_payloads" isDirectory:YES] path];
        }
    }
    // Sideloaded apps can lack App Group entitlement; diagnostics still work.
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/FBTweak/mobileconfig/fbt_fetch_payloads"];
}

static BOOL FBTStringContainsOneOf(NSString *text, NSArray<NSString *> *needles) {
    NSString *low = text.lowercaseString ?: @"";
    for (NSString *needle in needles) {
        if ([low containsString:needle]) return YES;
    }
    return NO;
}

static NSString *FBTRequestBodyTextForInspection(NSURLRequest *request) {
    NSData *body = request.HTTPBody;
    if (!body.length || body.length > 2 * 1024 * 1024) return @"";
    NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    return text ?: @"";
}

static NSDictionary *FBTQueryHashState(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return @{ @"query_hash_state": @"missing", @"query_hash_length": @0,
                  @"one_query_hash_state": @"missing", @"one_query_hash_length": @0 };
    }
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"(?i)[\"']?(one_query_hash|query_hash)[\"']?\\s*[:=]\\s*(?:[\"']([^\"']*)[\"']|([^,}&\\s]*))"
        options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches =
        [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    NSMutableDictionary *out = [@{
        @"query_hash_state": @"missing", @"query_hash_length": @0,
        @"one_query_hash_state": @"missing", @"one_query_hash_length": @0
    } mutableCopy];
    for (NSTextCheckingResult *match in matches) {
        NSString *key = [[text substringWithRange:[match rangeAtIndex:1]] lowercaseString];
        NSRange valueRange = [match rangeAtIndex:2];
        if (valueRange.location == NSNotFound) valueRange = [match rangeAtIndex:3];
        NSString *value = valueRange.location == NSNotFound ? @"" : [text substringWithRange:valueRange];
        BOOL empty = value.length == 0 || [value.lowercaseString isEqualToString:@"null"] ||
                     [value.lowercaseString isEqualToString:@"none"];
        NSString *prefix = [key isEqualToString:@"one_query_hash"] ? @"one_query_hash" : @"query_hash";
        out[[prefix stringByAppendingString:@"_state"]] = empty ? @"empty" : @"present";
        out[[prefix stringByAppendingString:@"_length"]] = @(empty ? 0 : value.length);
    }
    return out;
}

static BOOL FBTRequestLooksLikeQEInfoOrNameFetch(NSURLRequest *request, NSString **hostOut,
                                                  NSString **pathOut, NSDictionary **hashOut) {
    NSURL *url = request.URL;
    NSString *host = url.host ?: @"";
    NSString *path = url.path ?: @"";
    NSString *body = FBTRequestBodyTextForInspection(request);
    NSString *urlQuery = url.query ?: @"";
    NSString *probe = [NSString stringWithFormat:@"%@ %@ %@ %@", host, path, urlQuery, body];
    BOOL hasMarker = FBTStringContainsOneOf(probe, @[
        @"qe_info", @"qeinfo", @"qce", @"mobileconfig",
        @"params_names", @"param_names", @"parameter_names",
        @"fetch_names", @"refresh_names", @"query_hash", @"one_query_hash",
        @"fbmobileconfigqeinfo", @"get_param_info"
    ]);
    // GraphQL endpoints are only candidates when the request body itself contains
    // a MobileConfig/QE marker. We intentionally do not log URL query strings,
    // request headers or request-body contents.
    if (!hasMarker) return NO;
    if (hostOut) *hostOut = host;
    if (pathOut) *pathOut = path;
    if (hashOut) *hashOut = FBTQueryHashState([NSString stringWithFormat:@"%@\n%@", urlQuery, body]);
    return YES;
}

static BOOL FBTJSONHasCredentialField(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        for (id rawKey in (NSDictionary *)value) {
            if (![rawKey isKindOfClass:[NSString class]]) continue;
            NSString *key = [[(NSString *)rawKey lowercaseString]
                stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
            key = [key stringByReplacingOccurrencesOfString:@"." withString:@"_"];
            NSSet *credentialKeys = [NSSet setWithArray:@[
                @"authorization", @"proxy_authorization", @"cookie", @"set_cookie",
                @"access_token", @"oauth_token", @"refresh_token", @"auth_token",
                @"session_token", @"session_key", @"password", @"client_secret",
                @"app_secret", @"bearer_token"
            ]];
            id child = ((NSDictionary *)value)[rawKey];
            if ([credentialKeys containsObject:key] && child &&
                child != (id)kCFNull && !([child isKindOfClass:[NSString class]] && ![(NSString *)child length])) {
                return YES;
            }
            if (FBTJSONHasCredentialField(child)) return YES;
        }
    } else if ([value isKindOfClass:[NSArray class]]) {
        for (id child in (NSArray *)value) {
            if (FBTJSONHasCredentialField(child)) return YES;
        }
    }
    return NO;
}

static BOOL FBTTextLooksLikeCredentialPayload(NSString *text) {
    if (!text.length) return NO;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"(?i)[\"'](authorization|proxy_authorization|cookie|set-cookie|access[_-]?token|oauth[_-]?token|refresh[_-]?token|auth[_-]?token|session[_-]?(token|key)|password|client[_-]?secret|app[_-]?secret|bearer[_-]?token)[\"']\\s*:\\s*[\"'][^\"']+[\"']"
        options:0 error:nil];
    return [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static NSString *FBTSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)MIN(data.length, UINT32_MAX), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSString *FBTUTCNow(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    });
    @synchronized (formatter) {
        return [formatter stringFromDate:[NSDate date]] ?: @"";
    }
}

static NSDictionary *FBTCurrentCaptureArm(void) {
    [sCaptureLock lock];
    NSDictionary *state = nil;
    if (sCaptureReason.length && CACurrentMediaTime() <= sCaptureArmedUntil) {
        state = @{ @"reason": sCaptureReason, @"armed_until": @(sCaptureArmedUntil) };
    }
    [sCaptureLock unlock];
    return state;
}

NSDictionary *FBTMobileConfigResponseCaptureArmInfo(void) {
    return FBTCurrentCaptureArm() ?: @{};
}

BOOL FBTMobileConfigResponseCaptureShouldCaptureRequest(NSString *host, NSString *path, NSString *reason) {
    NSString *probe = [NSString stringWithFormat:@"%@ %@", host ?: @"", path ?: @""];
    NSArray<NSString *> *markers = @[
        @"qe_info", @"qeinfo", @"qce", @"mobileconfig", @"params_names",
        @"param_names", @"parameter_names", @"fetch_names", @"refresh_names",
        @"query_hash", @"one_query_hash", @"fbmobileconfigqeinfo", @"get_param_info",
        @"graphql"
    ];
    BOOL namedFlow = FBTStringContainsOneOf(probe, markers);
    BOOL forceWindow = [reason isEqualToString:@"force_name_download"] ||
                       [reason isEqualToString:@"qe_info_name_refresh"] ||
                       [reason isEqualToString:@"qe_info_param_fetch"];
    return namedFlow || (forceWindow && FBTStringContainsOneOf(probe, @[@"/api/", @"graphql"]));
}

void FBTMobileConfigResponseCaptureRecordTransportEvent(NSString *event, NSDictionary *details) {
    FBTMobileConfigFetchDiagnosticsRecord(event ?: @"transport_event", details ?: @{});
}

static void FBTSetCaptureStatus(NSString *status, NSString *absolutePath, NSString *relativePath) {
    [sCaptureLock lock];
    sLastCaptureStatus = status ?: @"unknown";
    if (absolutePath.length) sLastBodyPath = absolutePath;
    if (relativePath.length) sLastBodyRelativePath = relativePath;
    [sCaptureLock unlock];
}

static void FBTResponseCaptureWriteRawPayload(NSData *data, NSString *host, NSString *path,
        NSString *method, NSDictionary *queryHashState, NSString *captureReason,
        NSInteger httpStatus, NSString *contentType, NSString *transport) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    NSMutableDictionary *event = [@{
        @"request_host": host ?: @"",
        @"request_path": path ?: @"",
        @"request_method": method ?: @"",
        @"response_bytes": @(data.length),
        @"http_status": @(httpStatus),
        @"content_type": contentType ?: @"",
        @"capture_reason": captureReason ?: @"qe_info",
        @"transport": transport ?: @"unknown",
        @"body_capture_status": @"not_saved"
    } mutableCopy];
    for (NSString *key in @[@"request_id", @"http_status_source", @"native_tigon_correlation", @"experiment_id", @"experiment_profile", @"experiment_state", @"employee_field_added",
        @"authorization_state", @"authorization_scheme", @"authorization_credential_present", @"authorization_observation_stage"])
        if (queryHashState[key]) event[key] = queryHashState[key];
    NSDictionary *summary = FBTNamesResponseSummary(data);
    NSMutableDictionary *summaryEvent = [event mutableCopy];
    [summaryEvent addEntriesFromDictionary:summary];
    FBTMobileConfigFetchDiagnosticsRecord(@"names_transport_diagnostic", summaryEvent);
    NSString *decodeStatus = nil;
    NSData *decoded = FBTNamesDecodeResponse(data, &decodeStatus);
    if (!decoded || [summary[@"body_status"] isEqualToString:@"native_error_summary_NOT_server_JSON"]) {
        event[@"body_capture_status"] = summary[@"body_status"] ?: decodeStatus ?: @"decode_failed";
        FBTSetCaptureStatus(event[@"body_capture_status"], nil, nil);
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_skipped", event);
        return;
    }
    data = decoded;
    event[@"response_bytes"] = @(data.length);
    NSString *provenance = queryHashState[@"payload_provenance"] ?: @"http_response_body";
    event[@"payload_provenance"] = provenance;
    if (!data.length) {
        event[@"body_capture_status"] = @"empty_body";
        FBTSetCaptureStatus(@"empty_body", nil, nil);
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_skipped", event);
        return;
    }
    if (data.length > 2 * 1024 * 1024) {
        event[@"body_capture_status"] = @"over_2mb_limit";
        FBTSetCaptureStatus(@"over_2mb_limit", nil, nil);
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_skipped", event);
        return;
    }
    NSString *utf8 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!utf8) {
        event[@"body_capture_status"] = @"non_utf8_body_not_persisted";
        FBTSetCaptureStatus(@"non_utf8_body_not_persisted", nil, nil);
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_skipped", event);
        return;
    }
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
    BOOL credentialPayload = (parsed && FBTJSONHasCredentialField(parsed)) ||
                             FBTTextLooksLikeCredentialPayload(utf8);
    if (credentialPayload) {
        event[@"body_capture_status"] = @"credential_field_detected_not_persisted";
        FBTSetCaptureStatus(@"credential_field_detected_not_persisted", nil, nil);
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_skipped", event);
        return;
    }
    NSString *base = FBTResponseCaptureBasePath();
    if (!base.length) {
        event[@"body_capture_status"] = @"app_group_unavailable";
        FBTSetCaptureStatus(@"app_group_unavailable", nil, nil);
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_skipped", event);
        return;
    }
    NSError *fileError = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:&fileError]) {
        event[@"body_capture_status"] = @"directory_create_failed";
        FBTSetCaptureStatus(@"directory_create_failed", nil, nil);
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_skipped", event);
        return;
    }
    NSString *extension = parsed ? @"json" : @"txt";
    NSString *leaf = [NSString stringWithFormat:@"qe_payload_%@.%@", [NSUUID UUID].UUIDString, extension];
    NSString *absolutePath = [base stringByAppendingPathComponent:leaf];
    NSString *relativePath = [@"fbt_fetch_payloads/" stringByAppendingString:leaf];
    if (![data writeToFile:absolutePath options:NSDataWritingAtomic error:&fileError]) {
        event[@"body_capture_status"] = @"write_failed";
        FBTSetCaptureStatus(@"write_failed", nil, nil);
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_skipped", event);
        return;
    }
    NSString *sha = FBTSHA256(data);
    NSDictionary *metadata = @{
        @"captured_at_utc": FBTUTCNow(),
        @"payload_provenance": provenance,
        @"http_status_source": queryHashState[@"http_status_source"] ?: (httpStatus ? @"transport_response" : @"not_observed"),
        @"capture_reason": captureReason ?: @"qe_info",
        @"request_host": host ?: @"",
        @"request_path": path ?: @"",
        @"request_method": method ?: @"",
        @"http_status": @(httpStatus),
        @"content_type": contentType ?: @"",
        @"transport": transport ?: @"unknown",
        @"response_bytes": @(data.length),
        @"sha256": sha,
        @"query_hash_state": queryHashState[@"query_hash_state"] ?: @"missing",
        @"query_hash_length": queryHashState[@"query_hash_length"] ?: @0,
        @"one_query_hash_state": queryHashState[@"one_query_hash_state"] ?: @"missing",
        @"one_query_hash_length": queryHashState[@"one_query_hash_length"] ?: @0,
        @"body_file": relativePath
    };
    NSData *metaData = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:nil];
    if (metaData.length) [metaData writeToFile:[absolutePath stringByAppendingString:@".meta.json"] options:NSDataWritingAtomic error:nil];
    event[@"payload_file"] = relativePath;
    event[@"payload_sha256"] = sha;
    event[@"body_capture_status"] = @"saved_raw_bytes";
    FBTSetCaptureStatus(@"saved_raw_bytes", absolutePath, relativePath);
    [sCaptureLock lock];
    sCapturedBodyCount++;
    [sCaptureLock unlock];
    FBTMobileConfigFetchDiagnosticsRecord(@"network_response_body_captured", event);
}

void FBTMobileConfigResponseCaptureWriteRawBody(NSData *data, NSString *host, NSString *path,
        NSString *method, NSDictionary *queryHashState, NSString *reason, NSInteger httpStatus,
        NSString *contentType, NSString *transport) {
    FBTResponseCaptureWriteRawPayload(data, host, path, method, queryHashState, reason,
                                      httpStatus, contentType, transport);
}

static void FBTSaveResponseBody(NSData *data, NSURLResponse *response, NSError *networkError,
                                NSString *host, NSString *path, NSString *method,
                                NSDictionary *queryHashState, NSString *captureReason) {
    NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]]
        ? (NSHTTPURLResponse *)response : nil;
    NSInteger status = http ? http.statusCode : 0;
    NSString *contentType = @"";
    if (http) {
        for (id key in http.allHeaderFields) {
            if ([[[key description] lowercaseString] isEqualToString:@"content-type"]) {
                contentType = [http.allHeaderFields[key] description] ?: @"";
                break;
            }
        }
    }
    if (networkError) {
        FBTMobileConfigFetchDiagnosticsRecord(@"network_response_error", @{
            @"transport": @"NSURLSession",
            @"request_host": host ?: @"",
            @"request_path": path ?: @"",
            @"request_method": method ?: @"",
            @"network_error_domain": networkError.domain ?: @"",
            @"network_error_code": @(networkError.code),
            @"http_status": @(status)
        });
    }
    FBTMobileConfigResponseCaptureWriteRawBody(data, host, path, method, queryHashState,
        captureReason, status, contentType, @"NSURLSession");
}

static __thread NSUInteger sSessionCallDepth = 0;

static NSURLSessionDataTask *FBTSessionDataTaskWithOriginal(id self, SEL _cmd, NSURLRequest *request,
        void (^completionHandler)(NSData *, NSURLResponse *, NSError *), IMP originalImp) {
    if (!originalImp) return nil;
    if (sSessionCallDepth) {
        return ((FBTSessionDataTaskOrig)originalImp)(self, _cmd, request, completionHandler);
    }

    NSString *host = nil;
    NSString *path = nil;
    NSDictionary *hashState = nil;
    NSDictionary *arm = FBTCurrentCaptureArm();
    BOOL diagnosticsOn = [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
    BOOL relevant = diagnosticsOn && arm &&
        FBTRequestLooksLikeQEInfoOrNameFetch(request, &host, &path, &hashState);
    NSString *method = request.HTTPMethod ?: @"GET";
    if (relevant) {
        NSMutableDictionary *event = [@{
            @"request_host": host ?: @"",
            @"request_path": path ?: @"",
            @"request_method": method,
            @"request_body_bytes": @(request.HTTPBody.length),
            @"capture_reason": arm[@"reason"] ?: @"qe_info"
        } mutableCopy];
        [event addEntriesFromDictionary:hashState ?: @{}];
        FBTMobileConfigFetchDiagnosticsRecord(@"network_request_candidate", event);
    }

    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = completionHandler;
    if (relevant && completionHandler) {
        NSString *captureReason = arm[@"reason"] ?: @"qe_info";
        NSDictionary *copiedHashState = [hashState copy] ?: @{};
        NSString *copiedHost = [host copy] ?: @"";
        NSString *copiedPath = [path copy] ?: @"";
        NSString *copiedMethod = [method copy] ?: @"GET";
        wrappedCompletion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            @try {
                FBTSaveResponseBody(data, response, error, copiedHost, copiedPath, copiedMethod,
                                    copiedHashState, captureReason);
            } @catch (__unused NSException *exception) {
                FBTSetCaptureStatus(@"capture_exception", nil, nil);
            }
            completionHandler(data, response, error);
        };
    }
    FBTSessionDataTaskOrig orig = (FBTSessionDataTaskOrig)originalImp;
    ++sSessionCallDepth;
    @try { return orig(self, _cmd, request, wrappedCompletion); }
    @finally { --sSessionCallDepth; }
}

static BOOL FBTClassDefinesSelector(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) { found = YES; break; }
    }
    if (methods) free(methods);
    return found;
}

static BOOL FBTIsNSURLSessionSubclass(Class cls, Class sessionClass) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        if (current == sessionClass) return YES;
    }
    return NO;
}

static void FBTInstallURLSessionHookOnClass(Class cls, SEL selector, Class sessionClass) {
    if (!cls || !selector) return;
    if (cls != sessionClass && !FBTIsNSURLSessionSubclass(cls, sessionClass)) return;
    if (cls != sessionClass && !FBTClassDefinesSelector(cls, selector)) return;
    NSString *name = NSStringFromClass(cls) ?: @"unknown";
    [sCaptureLock lock];
    if ([sHookedSessionClasses containsObject:name]) { [sCaptureLock unlock]; return; }
    [sHookedSessionClasses addObject:name];
    [sCaptureLock unlock];

    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 4) {
        [sCaptureLock lock]; [sHookedSessionClasses removeObject:name]; [sCaptureLock unlock];
        return;
    }
    // Each class owns its forwarding IMP. Dynamic-class lookup would recurse
    // when a subclass implementation calls the hooked superclass method.
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^NSURLSessionDataTask *(id receiver, NSURLRequest *request,
            void (^completion)(NSData *, NSURLResponse *, NSError *)) {
        return FBTSessionDataTaskWithOriginal(receiver, selector, request, completion, original);
    });
    MSHookMessageEx(cls, selector, replacement, &original);
    if (original) {
        [sCaptureLock lock];
        sOriginalSessionImpByClass[name] = [NSValue valueWithPointer:original];
        [sCaptureLock unlock];
    } else {
        [sCaptureLock lock]; [sHookedSessionClasses removeObject:name]; [sCaptureLock unlock];
    }
}

void FBTMobileConfigResponseCaptureInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sCaptureLock = [[NSLock alloc] init];
        sOriginalSessionImpByClass = [NSMutableDictionary dictionary];
        sHookedSessionClasses = [NSMutableSet set];
    });
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    FBTMobileConfigResponseCaptureInstallTigon();
    FBTMobileConfigFetcherCaptureInstall();
    Class sessionClass = objc_getClass("NSURLSession");
    SEL selector = @selector(dataTaskWithRequest:completionHandler:);
    if (!sessionClass || !selector) {
        FBTMobileConfigFetchDiagnosticsRecord(@"response_body_hook", @{ @"hook_installed": @NO });
        return;
    }
    unsigned int count = 0;
    int classCount = objc_getClassList(NULL, 0);
    if (classCount > 0) {
        Class *classes = (Class *)calloc((size_t)classCount, sizeof(Class));
        if (classes) {
            count = (unsigned int)MIN(objc_getClassList(classes, classCount), classCount);
            FBTInstallURLSessionHookOnClass(sessionClass, selector, sessionClass);
            for (unsigned int i = 0; i < count; i++) {
                if (classes[i] != sessionClass && FBTIsNSURLSessionSubclass(classes[i], sessionClass)) {
                    FBTInstallURLSessionHookOnClass(classes[i], selector, sessionClass);
                }
            }
            free(classes);
        }
    }
    [sCaptureLock lock];
    sCaptureHookInstalled = sOriginalSessionImpByClass.count > 0;
    NSUInteger hookedCount = sOriginalSessionImpByClass.count;
    [sCaptureLock unlock];
    FBTMobileConfigFetchDiagnosticsRecord(@"response_body_hook", @{
        @"hook_installed": @(sCaptureHookInstalled),
        @"hooked_session_class_count": @(hookedCount),
        @"capture_surface": @"NSURLSession completion handlers; Tigon-native callbacks may bypass this surface"
    });
}

void FBTMobileConfigResponseCaptureArm(NSString *reason) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    FBTMobileConfigResponseCaptureInstall();
    [sCaptureLock lock];
    sCaptureReason = [reason copy] ?: @"qe_info";
    sCaptureArmedUntil = CACurrentMediaTime() + 45.0;
    sLastBodyPath = nil;
    sLastBodyRelativePath = nil;
    sLastCaptureStatus = @"armed_waiting_for_native_mc_response";
    [sCaptureLock unlock];
    FBTMobileConfigFetchDiagnosticsRecord(@"response_capture_armed", @{
        @"capture_reason": reason ?: @"qe_info",
        @"capture_window_seconds": @45
    });
}

void FBTMobileConfigResponseCaptureDisarm(void) {
    [sCaptureLock lock];
    sCaptureArmedUntil = 0;
    sCaptureReason = nil;
    sLastCaptureStatus = @"paused";
    [sCaptureLock unlock];
}

NSString *FBTMobileConfigResponseCaptureLastBodyString(void) {
    [sCaptureLock lock];
    NSString *path = [sLastBodyPath copy];
    [sCaptureLock unlock];
    if (!path.length && !sCaptureReason.length) {
        NSString *base = FBTResponseCaptureBasePath();
        if (!base.length) return @"";
        NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:base error:nil] ?: @[];
        NSDate *bestDate = nil;
        NSString *bestPath = nil;
        for (NSString *name in names) {
            if (![name hasPrefix:@"qe_payload_"] ||
                !([name hasSuffix:@".json"] || [name hasSuffix:@".txt"])) continue;
            NSString *candidate = [base stringByAppendingPathComponent:name];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:candidate error:nil];
            NSDate *date = attrs[NSFileModificationDate];
            if (date && (!bestDate || [date compare:bestDate] == NSOrderedDescending)) {
                bestDate = date;
                bestPath = candidate;
            }
        }
        path = bestPath;
        if (path.length) {
            [sCaptureLock lock];
            sLastBodyPath = path;
            sLastBodyRelativePath = [@"fbt_fetch_payloads/" stringByAppendingString:path.lastPathComponent];
            [sCaptureLock unlock];
        }
    }
    if (!path.length) return @"";
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @"";
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return body ?: @"";
}

NSDictionary *FBTMobileConfigResponseCaptureStatus(void) {
    [sCaptureLock lock];
    NSDictionary *status = @{
        @"hook_installed": @(sCaptureHookInstalled),
        @"armed": @(sCaptureReason.length > 0 && CACurrentMediaTime() <= sCaptureArmedUntil),
        @"capture_reason": sCaptureReason ?: @"",
        @"last_capture_status": sLastCaptureStatus ?: @"unknown",
        @"last_payload_file": sLastBodyRelativePath ?: @"",
        @"captured_body_count": @(sCapturedBodyCount),
        @"surface": @"NSURLSession callbacks; native Tigon hook status is reported separately"
    };
    [sCaptureLock unlock];
    NSMutableDictionary *combined = [status mutableCopy];
    NSDictionary *tigon = FBTMobileConfigTigonCaptureStatus();
    if (tigon) [combined addEntriesFromDictionary:tigon];
    [combined addEntriesFromDictionary:FBTMobileConfigFetcherCaptureStatus()];
    return [combined copy];
}


