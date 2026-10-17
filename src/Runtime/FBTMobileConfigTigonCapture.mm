#import "FBTMobileConfigResponseCapture.h"
#import "FBTMobileConfigFetchDiagnostics.h"
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
    if (!self || !sTigonCaptureLock || ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return nil;
    [sTigonCaptureLock lock];
    FBTTigonPruneLocked();
    NSValue *key = [NSValue valueWithPointer:self];
    NSMutableDictionary *context = sTigonCapturedRequests[key];
    if (!context && sPendingNativeRequests.count) {
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
        if (simple) {
            // Shared callbacks serve other products too. Restrict to the MC
            // endpoint, regardless of a broad force-download capture window.
            if ([path.lowercaseString rangeOfString:@"mobileconfig"].location == NSNotFound) return;
            reason = path.lastPathComponent;
        } else if (!FBTMobileConfigResponseCaptureShouldCaptureRequest(host, path, reason)) return;

        NSDictionary *hashState = @{};
        if (sTigonURLQuery) {
            const std::string &query = sTigonURLQuery(url);
            hashState = FBTTigonQueryHashState(query);
        } else {
            hashState = FBTTigonQueryHashState(std::string());
        }
        NSMutableDictionary *context = [@{
            @"transport": simple ? @"TigonSimpleCallbacks" : @"TigonForwardingRequestCallbacks",
            @"request_host": host ?: @"",
            @"request_path": path ?: @"",
            @"request_method": method ?: @"",
            @"capture_reason": reason,
            @"body": [NSMutableData data], @"mc_correlated": @YES, @"created": @(CACurrentMediaTime()),
            @"query_hash_source": hashState[@"query_hash_source"] ?: @"url_query_only"
        } mutableCopy];
        [context addEntriesFromDictionary:hashState];

        [sTigonCaptureLock lock];
        NSValue *key = [NSValue valueWithPointer:self];
        if (sTigonCapturedRequests.count >= 32) {
            NSValue *oldestKey = sTigonCapturedRequests.allKeys.firstObject;
            if (oldestKey) [sTigonCapturedRequests removeObjectForKey:oldestKey];
        }
        sTigonCapturedRequests[key] = context;
        [sTigonCaptureLock unlock];

        FBTTigonRecordContextEvent(@"tigon_request_started", context, @{
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
    if (!context || ![context[@"mc_correlated"] boolValue]) return;

    NSMutableData *body = [context[@"body"] isKindOfClass:[NSMutableData class]] ? context[@"body"] : nil;
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
    } else {
        FBTMobileConfigResponseCaptureWriteRawBody(body ?: [NSData data],
            context[@"request_host"], context[@"request_path"], context[@"request_method"],
            context, context[@"capture_reason"], [context[@"http_status"] integerValue], @"",
            context[@"transport"] ?: @"TigonForwardingRequestCallbacks");
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
            context[@"http_status_source"] = @"verified_tigon_response_status";
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
    [context addEntriesFromDictionary:request];
    context[@"mc_correlated"] = @YES;
    context[@"transport"] = @"TigonSimpleCallbacks";
    context[@"native_tigon_correlation"] = sCurrentSimpleIsError ? @"native_mc_completion_inside_simple_error" : @"native_mc_completion_inside_simple_eom";
    context[@"payload_provenance"] = @"http_response_body_before_native_status_conversion";
    if (!sCurrentSimpleIsError) {
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

static void FBTInstallSimpleHooks(void) {
    if (sSimpleHooksInstalled) return;
    static const unsigned char uuid[16] = {76,76,68,254,85,85,49,68,161,194,108,202,228,237,37,151};
    struct Slot { uint64_t address, target; void *replacement; void **original; };
    Slot slots[] = {
        {0x8100558ULL, 0x29324ULL, (void *)FBTSimpleOnStarted, (void **)&sSimpleStarted},
        {0x8100588ULL, 0xfde218ULL, (void *)FBTSimpleOnResponse, (void **)&sSimpleResponse},
        {0x8100590ULL, 0xfde24cULL, (void *)FBTSimpleOnBody, (void **)&sSimpleBody},
        {0x81005a0ULL, 0xfde27cULL, (void *)FBTSimpleOnEOM, (void **)&sSimpleEOM},
        {0x81005b0ULL, 0x3fdda18ULL, (void *)FBTSimpleOnError, (void **)&sSimpleError}
    };
    BOOL complete = YES;
    NSMutableArray *failures = [NSMutableArray array];
    for (const Slot &slot : slots) {
        NSString *failure = nil;
        BOOL ok = FBTRebindVerifiedImageConstSlot("FBSharedFramework", slot.address,
            uuid, slot.target, slot.replacement, slot.original, &failure);
        complete = complete && ok;
        if (!ok) [failures addObject:[NSString stringWithFormat:@"0x%llx:%@", (unsigned long long)slot.address, failure ?: @"unknown"]];
    }
    sSimpleHooksInstalled = complete;
    sSimpleFailure = [failures componentsJoinedByString:@"; "];
    FBTMobileConfigResponseCaptureRecordTransportEvent(@"tigon_simple_callback_hooks", @{
        @"hook_installed": @(complete), @"message": sSimpleFailure ?: @"",
        @"capture_surface": @"UUID-verified shared TigonSimpleCallbacks data slots; HTTP status/body before native error conversion"
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
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sTigonCaptureLock = [[NSLock alloc] init];
        sTigonCapturedRequests = [NSMutableDictionary dictionary];
        sPendingNativeRequests = [NSMutableDictionary dictionary];
    });
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    // Resolve only missing getters on each install attempt. Frameworks may
    // appear after launch; dispatch_once is only for local container setup.
    if (!sTigonRequestURL) sTigonRequestURL = (FBTTigonRequestURLFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon12TigonRequest3urlEv");
    if (!sTigonRequestMethod) sTigonRequestMethod = (FBTTigonStringGetterFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon12TigonRequest6methodEv");
    if (!sTigonURLHost) sTigonURLHost = (FBTTigonStringGetterFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon3url8TigonUrl7getHostEv");
    if (!sTigonURLPath) sTigonURLPath = (FBTTigonStringGetterFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon3url8TigonUrl7getPathEv");
    if (!sTigonURLQuery) sTigonURLQuery = (FBTTigonStringGetterFn)dlsym(RTLD_DEFAULT, "_ZNK8facebook5tigon3url8TigonUrl8getQueryEv");
    FBTInstallSimpleHooks();
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

