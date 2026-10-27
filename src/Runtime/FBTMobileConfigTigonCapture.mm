#import "FBTMobileConfigResponseCapture.h"
#import "FBTMCNativeSessionProbes.h"
#import "FBTMobileConfigFetchDiagnostics.h"
#import "FBTNetworkInspectorStore.h"
#import "FBTNamesResponseSummary.h"
#import <QuartzCore/QuartzCore.h>
#import "FBTDataSlotRebinding.h"
#import "../FBTDefaults.h"
#include "../../modules/fishhook/fishhook.h"
#include <dlfcn.h>
#include <string>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <atomic>
#include <cfloat>
#include <new>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>

// Theos includes CydiaSubstrate through FBTPrefix.h; declare the standard
// ABI explicitly for the portable Objective-C++ callback fixture as well.
extern "C" void MSHookFunction(void *symbol, void *replace, void **result);

typedef void (*FBTTigonStartedOrig)(void *, const void *);
typedef void (*FBTTigonBodyOrig)(void *, void *);
typedef void (*FBTTigonResponseOrig)(void *, void *);
typedef void (*FBTTigonEndOrig)(void *, void *);
typedef void (*FBTTigonErrorOrig)(void *, const void *, void *);

typedef const void *(*FBTTigonRequestURLFn)(const void *);
typedef const std::string &(*FBTTigonStringGetterFn)(const void *);

static FBTTigonStartedOrig sOrigTigonStarted = nullptr;
static FBTTigonBodyOrig sOrigTigonBody = nullptr;
static FBTTigonResponseOrig sOrigTigonResponse = nullptr;
static FBTTigonEndOrig sOrigTigonEOM = nullptr;
static FBTTigonErrorOrig sOrigTigonError = nullptr;
// MobileConfig uses this FBSharedFramework vtable, bypassing the main
// executable's forwarding callbacks. Keep each original separate.
static FBTTigonStartedOrig sSimpleStarted;
static FBTTigonBodyOrig sSimpleBody;
static FBTTigonResponseOrig sSimpleResponse;
static FBTTigonEndOrig sSimpleEOM;
static FBTTigonErrorOrig sSimpleError;
static BOOL sSimpleHooksInstalled;
static NSString *sSimpleFailure;
static void FBTInstallSimpleHooks(void);
static thread_local void *sCurrentSimpleEnd;
static thread_local BOOL sCurrentSimpleWasCaptured;
static thread_local BOOL sCurrentSimpleIsError;
static std::atomic<unsigned long long> sSimpleStartedCalls(0), sSimpleResponseCalls(0),
    sSimpleBodyCalls(0), sSimpleEOMCalls(0), sSimpleErrorCalls(0), sNativeCorrelations(0);
static std::atomic<unsigned long long> sStandaloneTigonIDs(1000000000000ULL);
static NSUInteger sSymbolDiscoveredSimpleHooks = 0;
static NSUInteger sExportedFunctionHooks = 0;
static BOOL sExportedOnStartedAvailable = NO;
static NSString *sSimpleInstallKind = @"not_installed";
struct FBTSimpleEndScope {
    void *previous;
    BOOL previousCaptured, previousError;
    FBTSimpleEndScope(void *current, BOOL captured, BOOL isError = NO)
        : previous(sCurrentSimpleEnd), previousCaptured(sCurrentSimpleWasCaptured), previousError(sCurrentSimpleIsError) {
        sCurrentSimpleEnd = current; sCurrentSimpleWasCaptured = captured; sCurrentSimpleIsError = isError;
    }
    ~FBTSimpleEndScope() { sCurrentSimpleEnd = previous; sCurrentSimpleWasCaptured = previousCaptured; sCurrentSimpleIsError = previousError; }
};

static FBTTigonRequestURLFn sTigonRequestURL = nullptr;
static FBTTigonStringGetterFn sTigonRequestMethod = nullptr;
static FBTTigonStringGetterFn sTigonURLHost = nullptr;
static FBTTigonStringGetterFn sTigonURLPath = nullptr;
static FBTTigonStringGetterFn sTigonURLQuery = nullptr;

// Verified in Shared 583: findHeader -> 0x45dd74 returns a 32-byte optional
// string indirectly in x8, with engagement at +0x18. Missing result has no
// live string. Destroy only an engaged copy; never retain/export its bytes.
struct alignas(8) FBTHeaderResult { unsigned char bytes[32]; };
using FBTFindHeaderFn = FBTHeaderResult (*)(const void *, const std::string &);
static FBTFindHeaderFn sFindHeader;
static_assert(sizeof(std::string) == 24, "Apple libc++ string ABI required");
static NSDictionary *FBTAuthorizationSummary(const std::string &value) {
    size_t start = value.find_first_not_of(" \t");
    if (start == std::string::npos) return @{@"authorization_state": @"empty", @"authorization_scheme": @"none", @"authorization_credential_present": @NO};
    size_t end = value.find_first_of(" \t", start);
    std::string scheme = value.substr(start, end == std::string::npos ? end : end-start);
    for (char &c : scheme) if (c >= 'A' && c <= 'Z') c += 'a'-'A';
    BOOL credential = end != std::string::npos && value.find_first_not_of(" \t", end) != std::string::npos;
    return @{@"authorization_state": @"present", @"authorization_scheme": scheme == "oauth" ? @"OAuth" : scheme == "bearer" ? @"Bearer" : @"other",
        @"authorization_credential_present": @(credential)};
}
static NSDictionary *FBTObserveRequestAuthorization(const void *request) {
    if (!sFindHeader) return @{@"authorization_state": @"not_observed", @"authorization_observation_stage": @"getter_unavailable_or_unverified"};
    for (const char *key : {"Authorization", "authorization"}) {
        FBTHeaderResult found = sFindHeader(request, std::string(key));
        if (!found.bytes[24]) continue;
        std::string *value = reinterpret_cast<std::string *>(found.bytes);
        NSMutableDictionary *summary = [FBTAuthorizationSummary(*value) mutableCopy];
        value->~basic_string();
        summary[@"authorization_observation_stage"] = @"TigonCallbacks.onStarted_not_wire_or_token_validation";
        return summary;
    }
    return @{@"authorization_state": @"not_found_by_native_lookup", @"authorization_observation_stage": @"TigonCallbacks.onStarted_not_wire_or_token_validation"};
}

// Only the known names are accessible with the verified findHeader getter.
// Exact values stay inside the opt-in on-device inspector, not the safe logs.
static NSString *FBTTigonString(const std::string &value);
static NSDictionary *FBTInspectorKnownHeaders(const void *request) {
    if (!sFindHeader || !request || !FBTNetworkInspectorIsCapturing()) return @{};
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    for (const char *name : {"Authorization", "Cookie", "Content-Type", "Accept", "User-Agent",
                             "X-FB-Friendly-Name", "X-FB-App-ID", "X-FB-Connection-Type", "X-FB-Device-Group"}) {
        FBTHeaderResult found = sFindHeader(request, std::string(name));
        if (!found.bytes[24]) continue;
        std::string *value = reinterpret_cast<std::string *>(found.bytes);
        if (value->size() <= 32768)
            items[[NSString stringWithUTF8String:name]] = FBTTigonString(*value);
        value->~basic_string();
    }
    return [items copy];
}

static NSLock *sTigonCaptureLock = nil;
static NSMutableDictionary<NSValue *, NSMutableDictionary *> *sTigonCapturedRequests = nil;
static NSMutableDictionary<NSNumber *, NSNumber *> *sPendingNativeRequests;
static NSUInteger sProvisionalEvictions;
static BOOL sTigonHooksInstalled = NO;
static int sTigonRebindStatus = -999;
static NSUInteger sTigonBodyCount = 0;
static BOOL sTigonBindingRegistered = NO;
static BOOL sTigonConstBodyInstalled = NO;
static BOOL sTigonConstResponseInstalled = NO;

// Layout verified against this FBSharedFramework build:
// folly::IOBuf::computeChainDataLength reads length at +0x00 and the
// next-chain pointer at +0x20; cloneCoalesced reads data at +0x08.
// Bodies are copied before forwarding ownership to the original callback.
struct FBTFollyIOBufLayout {
    uint64_t length;
    const uint8_t *data;
    uint64_t opaque10;
    const uint8_t *buffer;
    FBTFollyIOBufLayout *next;
    FBTFollyIOBufLayout *prev;
};
static_assert(offsetof(FBTFollyIOBufLayout, data) == 0x08, "IOBuf data offset mismatch");
static_assert(offsetof(FBTFollyIOBufLayout, next) == 0x20, "IOBuf chain offset mismatch");

static NSString *FBTTigonString(const std::string &value) {
    NSString *text = [[NSString alloc] initWithBytes:value.data()
                                              length:value.size()
                                            encoding:NSUTF8StringEncoding];
    return text ?: @"<non-UTF8>";
}

static NSDictionary *FBTTigonQueryHashState(const std::string &query) {
    NSMutableDictionary *state = [@{
        @"query_hash_state": @"missing",
        @"query_hash_length": @0,
        @"one_query_hash_state": @"missing",
        @"one_query_hash_length": @0,
        @"query_hash_source": @"url_query_only"
    } mutableCopy];
    size_t start = 0;
    while (start <= query.size()) {
        size_t end = query.find('&', start);
        if (end == std::string::npos) end = query.size();
        size_t eq = query.find('=', start);
        if (eq == std::string::npos || eq > end) eq = end;
        std::string key = query.substr(start, eq - start);
        std::string value = eq < end ? query.substr(eq + 1, end - eq - 1) : "";
        if (key == "query_hash" || key == "one_query_hash") {
            BOOL empty = value.empty() || value == "null" || value == "none";
            NSString *prefix = (key == "one_query_hash") ? @"one_query_hash" : @"query_hash";
            state[[prefix stringByAppendingString:@"_state"]] = empty ? @"empty" : @"present";
            state[[prefix stringByAppendingString:@"_length"]] = @(empty ? 0 : value.size());
        }
        if (end == query.size()) break;
        start = end + 1;
    }
    return state;
}

// Caller holds the map lock. Provisional bytes have a short lifetime and are
// never persisted until a native MC completion identifies the exact object.
static void FBTTigonPruneLocked(void) {
    double now = CACurrentMediaTime();
    for (NSNumber *key in sPendingNativeRequests.allKeys)
        if ([sPendingNativeRequests[key] doubleValue] < now) [sPendingNativeRequests removeObjectForKey:key];
    for (NSValue *key in sTigonCapturedRequests.allKeys) {
        NSDictionary *context = sTigonCapturedRequests[key];
        if (context[@"created"] && now - [context[@"created"] doubleValue] > 60) {
            [sTigonCapturedRequests removeObjectForKey:key]; ++sProvisionalEvictions;
        }
    }
}

void FBTMobileConfigTigonCaptureExpectRequest(NSDictionary *request) {
    NSNumber *key = request[@"request_id"];
    if (!key || !sTigonCaptureLock || ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    [sTigonCaptureLock lock];
    if (!sPendingNativeRequests) sPendingNativeRequests = [NSMutableDictionary dictionary];
    FBTTigonPruneLocked();
    if (sPendingNativeRequests.count < 32) sPendingNativeRequests[key] = @(CACurrentMediaTime() + 60);
    [sTigonCaptureLock unlock];
}

void FBTMobileConfigTigonCaptureCompleteRequest(NSNumber *key) {
    [sTigonCaptureLock lock];
    if (key) [sPendingNativeRequests removeObjectForKey:key];
    [sTigonCaptureLock unlock];
}

static NSMutableDictionary *FBTTigonContextForObject(void *self) {
    if (!self || !sTigonCaptureLock) return nil;
    [sTigonCaptureLock lock];
    NSMutableDictionary *context = sTigonCapturedRequests[[NSValue valueWithPointer:self]];
    [sTigonCaptureLock unlock];
    return context;
}

static NSMutableDictionary *FBTTigonProvisionalContext(void *self) {
    if (!FBTQEInvasiveHooksAllowed() && !FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey)) return nil;
    if (!self || !sTigonCaptureLock || ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return nil;
    [sTigonCaptureLock lock];
    FBTTigonPruneLocked();
    NSValue *key = [NSValue valueWithPointer:self];
    NSMutableDictionary *context = sTigonCapturedRequests[key];
    if (!context && (sPendingNativeRequests.count || FBTNetworkInspectorIsCapturing())) {
        if (sTigonCapturedRequests.count >= 32) {
            NSValue *oldest = nil; double earliest = DBL_MAX;
            for (NSValue *candidate in sTigonCapturedRequests) {
                double created = [sTigonCapturedRequests[candidate][@"created"] doubleValue];
                if (created < earliest) { earliest = created; oldest = candidate; }
            }
            if (oldest) { [sTigonCapturedRequests removeObjectForKey:oldest]; ++sProvisionalEvictions; }
        }
        context = [@{@"body": [NSMutableData data], @"created": @(CACurrentMediaTime()),
                     @"transport": @"TigonSimpleCallbacks", @"mc_correlated": @NO} mutableCopy];
        if (FBTNetworkInspectorIsCapturing()) {
            context[@"request_id"] = @(++sStandaloneTigonIDs);
            context[@"capture_reason"] = @"tigon_unclassified";
            context[@"inspector_standalone"] = @YES;
        }
        sTigonCapturedRequests[key] = context;
    }
    [sTigonCaptureLock unlock];
    return context;
}

static void FBTTigonRecordContextEvent(NSString *event, NSDictionary *context, NSDictionary *extra) {
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    if (context) {
        for (NSString *key in @[@"request_host", @"request_path", @"request_method",
                                @"capture_reason", @"request_id", @"http_status_source", @"native_tigon_correlation", @"query_hash_state", @"query_hash_length",
                                @"one_query_hash_state", @"one_query_hash_length", @"query_hash_source"]) {
            id value = context[key];
            if (value) details[key] = value;
        }
    }
    if (extra) [details addEntriesFromDictionary:extra];
    details[@"transport"] = context[@"transport"] ?: @"TigonForwardingRequestCallbacks";
    FBTMobileConfigResponseCaptureRecordTransportEvent(event, details);
}

static NSData *FBTCopyIOBufChain(void *rawHead, BOOL *tooLarge, BOOL *invalid) {
    if (tooLarge) *tooLarge = NO;
    if (invalid) *invalid = NO;
    if (!rawHead) return [NSData data];

    const NSUInteger maxBytes = 2 * 1024 * 1024;
    const NSUInteger maxSegments = 256;
    NSMutableData *copy = [NSMutableData data];
    FBTFollyIOBufLayout *head = (FBTFollyIOBufLayout *)rawHead;
    FBTFollyIOBufLayout *node = head;
    NSUInteger segments = 0;
    do {
        if (!node || segments++ >= maxSegments) {
            if (invalid) *invalid = YES;
            return nil;
        }
        uint64_t length = node->length;
        if (length > maxBytes || copy.length + (NSUInteger)length > maxBytes) {
            if (tooLarge) *tooLarge = YES;
            return nil;
        }
        if (length && !node->data) {
            if (invalid) *invalid = YES;
            return nil;
        }
        if (length) [copy appendBytes:node->data length:(NSUInteger)length];
        node = node->next;
    } while (node && node != head);
    if (!node || (segments >= maxSegments && node != head)) {
        if (invalid) *invalid = YES;
        return nil;
    }
    return [copy copy];
}

static void FBTTigonCaptureStarted(void *self, const void *request, BOOL simple) {
    if (!FBTQEInvasiveHooksAllowed() && !FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey)) return;
    if (!self || !request || ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    NSDictionary *arm = FBTMobileConfigResponseCaptureArmInfo();
    NSString *reason = [arm[@"reason"] isKindOfClass:[NSString class]] ? arm[@"reason"] : @"";
    if (!reason.length && !simple) return;
    if (simple) reason = @"mobileconfig_transport";

    if (!sTigonRequestURL || !sTigonURLHost || !sTigonURLPath || !sTigonRequestMethod) {
        FBTMobileConfigResponseCaptureRecordTransportEvent(@"tigon_request_metadata_unavailable", @{
            @"capture_reason": reason,
            @"query_hash_source": @"url_query_only"
        });
        return;
    }

    @try {
        const void *url = sTigonRequestURL(request);
        if (!url) return;
        NSString *host = FBTTigonString(sTigonURLHost(url));
        NSString *path = FBTTigonString(sTigonURLPath(url));
        NSString *method = FBTTigonString(sTigonRequestMethod(request));
        if ([host hasPrefix:@"<non-UTF8>"] || [path hasPrefix:@"<non-UTF8>"]) return;
        BOOL confirmedEndpoint = YES;
        if (simple) {
            confirmedEndpoint = [path.lowercaseString rangeOfString:@"mobileconfig"].location != NSNotFound;
            // A Graph/API route may carry the logical operation outside the URL
            // path. Keep only provisional metadata until the native callback
            // confirms this object belongs to an outstanding MC request.
            if (!confirmedEndpoint && !FBTTigonProvisionalContext(self)) return;
            if (confirmedEndpoint) reason = path.lastPathComponent;
        } else if (!FBTMobileConfigResponseCaptureShouldCaptureRequest(host, path, reason)) return;

        NSDictionary *hashState = @{};
        if (sTigonURLQuery) {
            const std::string &query = sTigonURLQuery(url);
            hashState = FBTTigonQueryHashState(query);
        } else {
            hashState = FBTTigonQueryHashState(std::string());
        }
        NSDictionary *earlier = simple ? FBTTigonContextForObject(self) : nil;
        NSMutableDictionary *context = [@{
            @"transport": simple ? @"TigonSimpleCallbacks" : @"TigonForwardingRequestCallbacks",
            @"request_host": FBTNamesRedactMessage(host ?: @""),
            @"request_path": FBTNamesRedactMessage(path ?: @""),
            @"request_method": method ?: @"",
            @"capture_reason": reason,
            @"body": [NSMutableData data], @"mc_correlated": @(confirmedEndpoint), @"created": @(CACurrentMediaTime()),
            @"query_hash_source": hashState[@"query_hash_source"] ?: @"url_query_only"
        } mutableCopy];
        [context addEntriesFromDictionary:hashState];
        if ([earlier[@"request_id"] isKindOfClass:NSNumber.class]) {
            context[@"request_id"] = earlier[@"request_id"];
            context[@"inspector_standalone"] = earlier[@"inspector_standalone"] ?: @NO;
        } else if (simple && FBTNetworkInspectorIsCapturing()) {
            context[@"request_id"] = @(++sStandaloneTigonIDs);
            context[@"inspector_standalone"] = @YES;
        }
        if (simple && !confirmedEndpoint && FBTNetworkInspectorIsCapturing())
            context[@"capture_reason"] = @"tigon_unclassified";
        [context addEntriesFromDictionary:FBTObserveRequestAuthorization(request)];
        if (FBTNetworkInspectorIsCapturing()) {
            context[@"inspector_raw_host"] = host ?: @"";
            context[@"inspector_raw_path"] = path ?: @"";
            if (sTigonURLQuery) context[@"inspector_query"] = FBTTigonString(sTigonURLQuery(url));
            context[@"inspector_headers"] = FBTInspectorKnownHeaders(request);
        }

        [sTigonCaptureLock lock];
        NSValue *key = [NSValue valueWithPointer:self];
        if (sTigonCapturedRequests.count >= 32) {
            NSValue *oldestKey = sTigonCapturedRequests.allKeys.firstObject;
            if (oldestKey) [sTigonCapturedRequests removeObjectForKey:oldestKey];
        }
        sTigonCapturedRequests[key] = context;
        [sTigonCaptureLock unlock];

        if (confirmedEndpoint) FBTTigonRecordContextEvent(@"tigon_request_started", context, @{
            @"request_body_persisted": @NO,
            @"query_hash_state": hashState[@"query_hash_state"] ?: @"missing",
            @"one_query_hash_state": hashState[@"one_query_hash_state"] ?: @"missing"
        });
    } @catch (__unused NSException *exception) {
        FBTMobileConfigResponseCaptureRecordTransportEvent(@"tigon_request_metadata_exception", @{
            @"capture_reason": reason
        });
    }
}

static void FBTTigonOnStarted(void *self, const void *request) {
    // Capture before forwarding: the original can invoke downstream callbacks.
    FBTTigonCaptureStarted(self, request, NO);
    if (sOrigTigonStarted) sOrigTigonStarted(self, request);
}

static void FBTTigonCaptureBody(void *self, void *uniquePtrArgument) {
    NSMutableDictionary *context = FBTTigonContextForObject(self);
    if (context && uniquePtrArgument &&
        [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        @synchronized (context) { @try {
            void *head = *(void **)uniquePtrArgument; // ABI: move-only unique_ptr is passed indirectly.
            BOOL tooLarge = NO;
            BOOL invalid = NO;
            NSData *chunk = FBTCopyIOBufChain(head, &tooLarge, &invalid);
            NSMutableData *body = [context[@"body"] isKindOfClass:[NSMutableData class]] ? context[@"body"] : nil;
            if (tooLarge || (chunk && body && body.length + chunk.length > 2 * 1024 * 1024)) {
                [body setLength:0];
                context[@"body_capture_status"] = @"over_2mb_limit";
            } else if (invalid || !chunk || !body) {
                [body setLength:0];
                context[@"body_capture_status"] = @"iobuf_copy_failed";
            } else if (!context[@"body_capture_status"]) {
                [body appendData:chunk];
            }
        } @catch (__unused NSException *exception) {
            [(NSMutableData *)context[@"body"] setLength:0];
            context[@"body_capture_status"] = @"iobuf_copy_exception";
        } }
    }
}

static void FBTTigonOnBody(void *self, void *uniquePtrArgument) {
    FBTTigonCaptureBody(self, uniquePtrArgument);
    if (sOrigTigonBody) sOrigTigonBody(self, uniquePtrArgument);
}

static void FBTTigonOnResponse(void *self, void *response) {
    NSDictionary *context = FBTTigonContextForObject(self);
    if (context) {
        FBTTigonRecordContextEvent(@"tigon_response_received", context, @{
            @"http_status": @0,
            @"http_status_source": @"not_exposed_by_hooked_callback"
        });
    }
    if (sOrigTigonResponse) sOrigTigonResponse(self, response);
}

static void FBTTigonFinishCapture(void *self) {
    NSDictionary *context = FBTTigonContextForObject(self);
    if (context) {
        [sTigonCaptureLock lock];
        [sTigonCapturedRequests removeObjectForKey:[NSValue valueWithPointer:self]];
        [sTigonCaptureLock unlock];
    }
    if (!context) return;
    BOOL correlated = [context[@"mc_correlated"] boolValue];
    BOOL inspected = FBTNetworkInspectorIsCapturing() && context[@"request_id"] != nil;
    if (!correlated && !inspected) return;

    NSMutableData *body = [context[@"body"] isKindOfClass:[NSMutableData class]] ? context[@"body"] : nil;
    if (FBTNetworkInspectorIsCapturing() && context[@"request_id"]) {
        FBTNetworkInspectorRecordTigon(context, body);
    }
    if (!correlated) {
        [sTigonCaptureLock lock];
        sTigonBodyCount++;
        [sTigonCaptureLock unlock];
        return; // Unclassified traffic remains inside the opt-in inspector.
    }
    NSString *captureStatus = [context[@"body_capture_status"] isKindOfClass:[NSString class]]
        ? context[@"body_capture_status"] : @"ready";
    if ([captureStatus isEqualToString:@"ready"] && !body.length) captureStatus = @"not_delivered_to_observed_callback";
    if (![captureStatus isEqualToString:@"ready"] ||
        [captureStatus isEqualToString:@"iobuf_copy_failed"] ||
        [captureStatus isEqualToString:@"iobuf_copy_exception"]) {
        FBTTigonRecordContextEvent(@"names_transport_diagnostic", context, @{
            @"body_status": captureStatus, @"response_bytes": @(body.length),
            @"http_status": context[@"http_status"] ?: @0
        });
        FBTTigonRecordContextEvent(@"tigon_response_body_unavailable", context, @{
            @"body_capture_status": captureStatus,
            @"response_bytes": @(body.length)
        });
    } else if (FBTQEInvasiveHooksAllowed()) {
        FBTMobileConfigResponseCaptureWriteRawBody(body ?: [NSData data],
            context[@"request_host"], context[@"request_path"], context[@"request_method"],
            context, context[@"capture_reason"], [context[@"http_status"] integerValue], @"",
            context[@"transport"] ?: @"TigonForwardingRequestCallbacks");
    } else {
        // Opt-in session probe writes only metadata; no response body on disk.
        FBTTigonRecordContextEvent(@"tigon_native_response_metadata", context, @{
            @"response_bytes": @(body.length), @"http_status": context[@"http_status"] ?: @0
        });
    }
    [sTigonCaptureLock lock];
    sTigonBodyCount++;
    [sTigonCaptureLock unlock];
}

static void FBTTigonOnEOM(void *self, void *summary) {
    FBTTigonFinishCapture(self);
    if (sOrigTigonEOM) sOrigTigonEOM(self, summary);
}

// All shared callbacks forward the same pointer/ownership to their own
// original exactly once. No status conversion or native retry is changed.
static void FBTSimpleOnStarted(void *self, const void *request) {
    ++sSimpleStartedCalls;
    FBTTigonCaptureStarted(self, request, YES);
    if (sSimpleStarted) sSimpleStarted(self, request);
}
static void FBTSimpleOnBody(void *self, void *body) {
    ++sSimpleBodyCalls;
    FBTTigonProvisionalContext(self);
    FBTTigonCaptureBody(self, body);
    if (sSimpleBody) sSimpleBody(self, body);
}
static void FBTSimpleOnResponse(void *self, void *response) {
    ++sSimpleResponseCalls;
    NSMutableDictionary *context = FBTTigonProvisionalContext(self);
    if (context && response && [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        // TigonResponse move constructor at 0xfde234 loads status with ldrh
        // from +0; SimpleCallbacks EOM reads the moved status at self+0x48.
        uint16_t status = 0;
        memcpy(&status, response, sizeof(status));
        if (status >= 100 && status <= 599) {
            context[@"http_status"] = @(status);
            context[@"http_status_source"] = sExportedFunctionHooks ?
                @"observed_response_status_candidate_unverified_build_layout" :
                @"verified_tigon_response_status";
        }
        context[@"payload_provenance"] = @"http_response_body_before_native_status_conversion";
        if ([context[@"mc_correlated"] boolValue]) FBTTigonRecordContextEvent(@"tigon_response_received", context, @{
            @"http_status": context[@"http_status"] ?: @0,
            @"http_status_source": context[@"http_status_source"] ?: @"not_observed"
        });
    }
    if (sSimpleResponse) sSimpleResponse(self, response);
}
static void FBTSimpleOnEOM(void *self, void *summary) {
    ++sSimpleEOMCalls;
    FBTSimpleEndScope scope(self, NO);
    @try { if (sSimpleEOM) sSimpleEOM(self, summary); }
    @finally { FBTTigonFinishCapture(self); }
}
static void FBTSimpleOnError(void *self, const void *error, void *summary) {
    ++sSimpleErrorCalls;
    FBTTigonProvisionalContext(self);
    FBTSimpleEndScope scope(self, NO, YES);
    @try { if (sSimpleError) sSimpleError(self, error, summary); }
    @finally { FBTTigonFinishCapture(self); }
}

NSDictionary *FBTMobileConfigTigonCaptureObserveNativeCompletion(NSDictionary *request, BOOL success) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return @{};
    if (!sCurrentSimpleEnd) return @{@"native_tigon_correlation": @"no_simple_terminal_scope"};
    ++sNativeCorrelations;
    NSMutableDictionary *context = FBTTigonContextForObject(sCurrentSimpleEnd);
    if (!context) context = [@{@"body": [NSMutableData data], @"transport": @"TigonSimpleCallbacks"} mutableCopy];
    if (!context[@"authorization_state"]) {
        context[@"authorization_state"] = @"not_observed";
        context[@"authorization_observation_stage"] = @"onStarted_not_observed_for_this_request";
    }
    [context addEntriesFromDictionary:request];
    context[@"mc_correlated"] = @YES;
    context[@"transport"] = @"TigonSimpleCallbacks";
    context[@"native_tigon_correlation"] = sCurrentSimpleIsError ? @"native_mc_completion_inside_simple_error" : @"native_mc_completion_inside_simple_eom";
    context[@"payload_provenance"] = @"http_response_body_before_native_status_conversion";
    if (!sCurrentSimpleIsError && !sExportedFunctionHooks) {
        // self+0x48/status and self+0x80/body were decompiled only for the
        // original UUID. Never dereference version-specific C++ object offsets
        // in symbol-entry fallback on an unknown build.
        uint16_t status = 0;
        memcpy(&status, (const uint8_t *)sCurrentSimpleEnd + 0x48, sizeof(status));
        if (status >= 100 && status <= 599) {
            context[@"http_status"] = @(status);
            context[@"http_status_source"] = @"verified_simple_callbacks_response_state";
        }
        // Fallback for onStarted/onBody not dispatched through the observed slots.
        if (!success && status >= 400 && ![context[@"body"] length] && !context[@"body_capture_status"]) {
            void *head = nullptr;
            memcpy(&head, (const uint8_t *)sCurrentSimpleEnd + 0x80, sizeof(head));
            BOOL tooLarge = NO, invalid = NO;
            NSData *body = FBTCopyIOBufChain(head, &tooLarge, &invalid);
            if (tooLarge || invalid) context[@"body_capture_status"] = tooLarge ? @"over_2mb_limit" : @"iobuf_copy_failed";
            else if (body.length) {
                context[@"body"] = [body mutableCopy];
                context[@"payload_provenance"] = @"http_error_body_retained_during_native_mc_completion";
            }
        }
    }
    NSMutableDictionary *details = [context mutableCopy];
    details[@"response_body_bytes"] = @([context[@"body"] length]);
    [details removeObjectForKey:@"body"];
    [sTigonCaptureLock lock];
    sTigonCapturedRequests[[NSValue valueWithPointer:sCurrentSimpleEnd]] = context;
    [sTigonCaptureLock unlock];
    // Snapshot/persist while still inside the original callback and before any
    // native teardown. Unrelated SimpleCallbacks never reach this promotion.
    FBTTigonFinishCapture(sCurrentSimpleEnd);
    sCurrentSimpleWasCaptured = YES;
    return details;
}

// vtable slots can hold compiler thunks or pointer-authenticated targets even
// when the class exports the C++ callback methods. Prefer the verified vtable,
// but allow a method-entry trampoline as a separate (non-vtable) fallback.
// A dynamic symbol is the only supported installation anchor. Legacy UUID/RVA
// anchors are deliberately not used here: another IPA's Mach-O UUID is not
// evidence that its vtable layout/ABI is compatible with this process.
//
// IMPORTANT: onResponse is the discovery anchor for EVERY callback. Installing
// its hook before onBody/onEOM/onError replaces that anchor in the live vtable,
// making later lookups report ambiguous_or_missing_vtable_anchor. Resolve and
// install onResponse LAST. Never retry a partially modified vtable, and never
// chain a method-entry MSHookFunction fallback onto partially hooked slots.
static BOOL sSimpleInstallAttempted = NO;
static void FBTInstallSimpleHooks(void) {
    if (sSimpleHooksInstalled || sSimpleInstallAttempted) return;

    static const char *vtableSymbol = "_ZTVN8facebook5tigon20TigonSimpleCallbacksE";
    static const char *responseSymbol =
        "_ZN8facebook5tigon20TigonSimpleCallbacks10onResponseEONS0_13TigonResponseE";
    static const char *methodSymbols[] = {
        "_ZN8facebook5tigon20TigonSimpleCallbacks9onStartedERKNS0_12TigonRequestE",
        "_ZN8facebook5tigon20TigonSimpleCallbacks10onResponseEONS0_13TigonResponseE",
        "_ZN8facebook5tigon20TigonSimpleCallbacks6onBodyENSt3__110unique_ptrIN5folly5IOBufENS2_14default_deleteIS5_EEEE",
        "_ZN8facebook5tigon20TigonSimpleCallbacks5onEOMEONS0_12TigonSummaryE",
        "_ZN8facebook5tigon20TigonSimpleCallbacks7onErrorERKNS0_10TigonErrorEONS0_12TigonSummaryE"
    };
    static const int relativeToResponse[] = {-6, 0, 1, 3, 5};
    struct Slot { void *replacement; void **original; };
    Slot slots[] = {
        {(void *)FBTSimpleOnStarted, (void **)&sSimpleStarted},
        {(void *)FBTSimpleOnResponse, (void **)&sSimpleResponse},
        {(void *)FBTSimpleOnBody, (void **)&sSimpleBody},
        {(void *)FBTSimpleOnEOM, (void **)&sSimpleEOM},
        {(void *)FBTSimpleOnError, (void **)&sSimpleError}
    };
    if (!dlsym(RTLD_DEFAULT, vtableSymbol) || !dlsym(RTLD_DEFAULT, responseSymbol)) {
        // May be called before FBSharedFramework is loaded. Allow a later
        // install attempt once the symbols become available.
        sSimpleFailure = @"dynamic_vtable_symbols_not_loaded";
        sSimpleInstallKind = @"awaiting_shared_framework";
        return;
    }
    sSimpleInstallAttempted = YES;
    // The reference/anchor (method 1) must be patched LAST.
    static const NSUInteger installationOrder[] = {0, 2, 3, 4, 1};
    NSMutableArray *failures = [NSMutableArray array];
    NSUInteger installed = 0;
    for (NSUInteger j = 0; j < sizeof(installationOrder) / sizeof(installationOrder[0]); ++j) {
        NSUInteger n = installationOrder[j];
        NSString *failure = nil;
        BOOL ok = FBTRebindImageVtableSlotBySymbols("FBSharedFramework",
            vtableSymbol, responseSymbol, methodSymbols[n],
            relativeToResponse[n], slots[n].replacement, slots[n].original, &failure);
        if (ok) {
            ++installed;
        } else {
            [failures addObject:[NSString stringWithFormat:@"method%lu:%@",
                (unsigned long)n, failure ?: @"symbol_binding_failed"]];
            // Never attempt method-entry trampolines after a vtable write, or
            // try to reinstall already replaced callbacks in this process.
            break;
        }
    }
    sSymbolDiscoveredSimpleHooks = installed;
    sExportedFunctionHooks = 0;
    sExportedOnStartedAvailable = NO;
    sSimpleHooksInstalled = (installed == 5);
    sSimpleInstallKind = sSimpleHooksInstalled ?
        @"dynamic_symbol_vtable_anchor_last" : installed ?
        @"partial_dynamic_vtable_no_retry" : @"dynamic_vtable_unsupported_build";
    sSimpleFailure = [failures componentsJoinedByString:@"; "];
    FBTMobileConfigResponseCaptureRecordTransportEvent(@"tigon_vtable_discovery", @{
        @"dynamic_symbols_installed": @(installed),
        @"legacy_uuid_installed": @0,
        @"exported_function_hooks_installed": @0,
        @"exported_onStarted_installed": @NO,
        @"hook_kind": sSimpleInstallKind,
        @"all_callbacks_installed": @(sSimpleHooksInstalled),
        @"failure": sSimpleFailure ?: @"",
        @"match_type": sSimpleHooksInstalled ?
            @"live_CXX_symbols_anchor_last" : @"unsupported_or_partial_no_retry"
    });
    FBTMobileConfigResponseCaptureRecordTransportEvent(@"tigon_simple_callback_hooks", @{
        @"hook_installed": @(sSimpleHooksInstalled),
        @"message": sSimpleFailure ?: @"",
        @"capture_surface": @"Live symbol-verified TigonSimpleCallbacks vtable (anchor patched last); original native callback forwarded once"
    });
}

static void FBTTigonOnError(void *self, const void *error, void *summary) {
    NSDictionary *context = FBTTigonContextForObject(self);
    if (context) {
        FBTTigonRecordContextEvent(@"tigon_network_error", context, @{
            @"error_object_present": @(error != nullptr)
        });
    }
    FBTTigonFinishCapture(self);
    if (sOrigTigonError) sOrigTigonError(self, error, summary);
}

NSDictionary *FBTMobileConfigTigonCaptureStatus(void) {
    if (!sTigonCaptureLock) {
        return @{
            @"tigon_hooks_installed": @NO,
            @"tigon_request_hook_installed": @NO,
            @"tigon_body_hook_installed": @NO,
            @"tigon_response_hook_installed": @NO,
            @"tigon_eom_hook_installed": @NO,
            @"tigon_error_hook_installed": @NO,
            @"tigon_rebind_status": @-999,
            @"tigon_completed_response_count": @0,
            @"tigon_context_count": @0
        };
    }
    [sTigonCaptureLock lock];
    FBTTigonPruneLocked();
    NSDictionary *status = @{
        @"pending_native_requests": @(sPendingNativeRequests.count),
        @"provisional_evictions": @(sProvisionalEvictions),
        @"simple_started_calls": @(sSimpleStartedCalls.load()),
        @"simple_response_calls": @(sSimpleResponseCalls.load()),
        @"simple_body_calls": @(sSimpleBodyCalls.load()),
        @"simple_eom_calls": @(sSimpleEOMCalls.load()),
        @"simple_error_calls": @(sSimpleErrorCalls.load()),
        @"native_tigon_correlations": @(sNativeCorrelations.load()),
        @"simple_callback_hooks_installed": @(sSimpleHooksInstalled),
        @"simple_symbol_resolved_callbacks": @(sSymbolDiscoveredSimpleHooks),
        @"simple_exported_function_hooks": @(sExportedFunctionHooks),
        @"simple_exported_onStarted_available": @(sExportedOnStartedAvailable),
        @"simple_hook_kind": sSimpleInstallKind ?: @"unknown",
        @"simple_callback_failure": sSimpleFailure ?: @"not_attempted",
        @"tigon_hooks_installed": @(sTigonHooksInstalled),
        @"tigon_request_hook_installed": @(sOrigTigonStarted != nullptr),
        @"tigon_body_hook_installed": @(sTigonConstBodyInstalled),
        @"tigon_response_hook_installed": @(sTigonConstResponseInstalled),
        @"tigon_eom_hook_installed": @(sOrigTigonEOM != nullptr),
        @"tigon_error_hook_installed": @(sOrigTigonError != nullptr),
        @"tigon_rebind_status": @(sTigonRebindStatus),
        @"tigon_completed_response_count": @(sTigonBodyCount),
        @"tigon_context_count": @(sTigonCapturedRequests.count)
    };
    [sTigonCaptureLock unlock];
    return status;
}

void FBTMobileConfigResponseCaptureInstallTigon(void) {
    // The session-only UI toggle enables only the ABI-checked SimpleCallbacks
    // data slots. Global forwarding/NSURLSession interception stays quarantined.
    if (!FBTQEInvasiveHooksAllowed() && !FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey)) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sTigonCaptureLock = [[NSLock alloc] init];
        sTigonCapturedRequests = [NSMutableDictionary dictionary];
        sPendingNativeRequests = [NSMutableDictionary dictionary];
    });
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    // Resolve only missing getters on each install attempt. Frameworks may
    // appear after launch; dispatch_once is only for local container setup.
    // url() returns const std::string& at request+0x68, not TigonUrl.
    // getTigonUrl() returns the parsed object used by component getters.
    if (!sTigonRequestURL) sTigonRequestURL = (FBTTigonRequestURLFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon12TigonRequest11getTigonUrlEv");
    if (!sTigonRequestMethod) sTigonRequestMethod = (FBTTigonStringGetterFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon12TigonRequest6methodEv");
    if (!sTigonURLHost) sTigonURLHost = (FBTTigonStringGetterFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon3url8TigonUrl7getHostEv");
    if (!sTigonURLPath) sTigonURLPath = (FBTTigonStringGetterFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon3url8TigonUrl7getPathEv");
    if (!sTigonURLQuery) sTigonURLQuery = (FBTTigonStringGetterFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon3url8TigonUrl8getQueryEv");
    FBTInstallSimpleHooks();
    // Read-only known-header lookup; validate image and RVA before calling.
    if (!sFindHeader && sSimpleHooksInstalled) {
        void *candidate = dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon12TigonRequest10findHeaderERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEE");
        Dl_info info = {};
        if (candidate && dladdr(candidate, &info) && info.dli_fname &&
            strcmp(strrchr(info.dli_fname, '/') ? strrchr(info.dli_fname, '/')+1 : info.dli_fname, "FBSharedFramework") == 0)
            sFindHeader = (FBTFindHeaderFn)candidate;
    }
    if (!FBTQEInvasiveHooksAllowed()) return; // Session probe ends here; no fishhook or global callbacks.
    if (!sFindHeader && sSimpleHooksInstalled) {
        void *candidate = dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon12TigonRequest10findHeaderERKNSt3__112basic_stringIcNS2_11char_traitsIcEENS2_9allocatorIcEEEE");
        Dl_info info = {};
        if (candidate && dladdr(candidate, &info) && info.dli_fname &&
            strcmp(strrchr(info.dli_fname, '/') ? strrchr(info.dli_fname, '/')+1 : info.dli_fname, "FBSharedFramework") == 0)
            sFindHeader = (FBTFindHeaderFn)candidate;
    }
    if (sTigonHooksInstalled) return;

    struct rebinding bindings[] = {
        { "_ZN8facebook5tigon31TigonForwardingRequestCallbacks9onStartedERKNS0_12TigonRequestE",
          (void *)FBTTigonOnStarted, (void **)&sOrigTigonStarted },
        { "_ZN8facebook5tigon31TigonForwardingRequestCallbacks6onBodyENSt3__110unique_ptrIN5folly5IOBufENS2_14default_deleteIS5_EEEE",
          (void *)FBTTigonOnBody, (void **)&sOrigTigonBody },
        { "_ZN8facebook5tigon31TigonForwardingRequestCallbacks10onResponseEONS0_13TigonResponseE",
          (void *)FBTTigonOnResponse, (void **)&sOrigTigonResponse },
        { "_ZN8facebook5tigon31TigonForwardingRequestCallbacks5onEOMEONS0_12TigonSummaryE",
          (void *)FBTTigonOnEOM, (void **)&sOrigTigonEOM },
        { "_ZN8facebook5tigon31TigonForwardingRequestCallbacks7onErrorERKNS0_10TigonErrorEONS0_12TigonSummaryE",
          (void *)FBTTigonOnError, (void **)&sOrigTigonError }
    };
    if (!sTigonBindingRegistered) {
        sTigonRebindStatus = rebind_symbols(bindings, sizeof(bindings) / sizeof(bindings[0]));
        sTigonBindingRegistered = (sTigonRebindStatus == 0);
    }
    // UUID + binding addresses revalidated with LIEF against the supplied IPA.
    // These two vtable slots are regular data, outside fishhook's pointer sections.
    static const unsigned char uuid[16] = {76,76,68,170,85,85,49,68,161,142,1,71,65,237,25,11};
    NSString *bodyFailure = nil, *responseFailure = nil;
    sTigonConstBodyInstalled = FBTRebindVerifiedMainConstSlot(0x101010378ULL, uuid,
        bindings[1].name, (void *)FBTTigonOnBody, (void **)&sOrigTigonBody, &bodyFailure);
    sTigonConstResponseInstalled = FBTRebindVerifiedMainConstSlot(0x101010370ULL, uuid,
        bindings[2].name, (void *)FBTTigonOnResponse, (void **)&sOrigTigonResponse, &responseFailure);
    sTigonHooksInstalled = (sOrigTigonStarted != nullptr && sTigonConstBodyInstalled &&
                            sTigonConstResponseInstalled && sOrigTigonEOM != nullptr &&
                            sOrigTigonError != nullptr);
    FBTMobileConfigResponseCaptureRecordTransportEvent(@"tigon_callback_hooks", @{
        @"hook_installed": @(sTigonHooksInstalled),
        @"tigon_request_hook_installed": @(sOrigTigonStarted != nullptr),
        @"tigon_body_hook_installed": @(sTigonConstBodyInstalled),
        @"tigon_response_hook_installed": @(sTigonConstResponseInstalled),
        @"tigon_eom_hook_installed": @(sOrigTigonEOM != nullptr),
        @"tigon_error_hook_installed": @(sOrigTigonError != nullptr),
        @"rebind_status": @(sTigonRebindStatus),
        @"request_url_getter_available": @(sTigonRequestURL != nullptr),
        @"request_method_getter_available": @(sTigonRequestMethod != nullptr),
        @"url_components_available": @(sTigonURLHost != nullptr && sTigonURLPath != nullptr),
        @"body_capture_status": bodyFailure ?: @"",
        @"message": responseFailure ?: @"",
        @"capture_surface": @"imports plus UUID-verified main executable data slots; response status is not exposed yet"
    });
}



