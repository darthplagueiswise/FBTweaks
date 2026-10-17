#import "FBTMobileConfigResponseCapture.h"
#import "FBTMobileConfigFetchDiagnostics.h"
#import "FBTDataSlotRebinding.h"
#import "../FBTDefaults.h"
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>
#include <atomic>
#include <algorithm>
#import <QuartzCore/QuartzCore.h>

using FBTMCCompletion = std::function<void(bool, const std::string &)>;
using FBTMCRequestPairs = std::vector<std::pair<std::string, std::string>>;
// RTTI and ARM64 call site 0x4bf0cc4 confirm all six payload arguments.
// The final optional<mc_stack_target_t> is opaque and unused by this target;
// forwarding its register unchanged avoids reconstructing a private enum.
using FBTMCAsyncFetchFn = void (*)(const void *, const std::string &, const std::string &,
    const FBTMCRequestPairs &, FBTMCCompletion, const std::string &, uint64_t);
static FBTMCAsyncFetchFn sOriginalFetch;
static BOOL sFetcherInstalled;
static NSString *sFetcherFailure;
static std::atomic<unsigned long long> sRequests(0), sResponses(0), sFailures(0);

struct FBTMCFetchObservation { std::atomic<int> httpStatus{0}; };
static thread_local std::shared_ptr<FBTMCFetchObservation> sObservation;
struct FBTMCFetchScope {
    std::shared_ptr<FBTMCFetchObservation> previous, current;
};
void *FBTMobileConfigFetcherCaptureBeginScope(void) {
    auto scope = new FBTMCFetchScope{sObservation, std::make_shared<FBTMCFetchObservation>()};
    sObservation = scope->current;
    return scope;
}
NSInteger FBTMobileConfigFetcherCaptureCurrentHTTPStatus(void) {
    return sObservation ? sObservation->httpStatus.load() : 0;
}
NSInteger FBTMobileConfigFetcherCaptureEndScope(void *opaque) {
    if (!opaque) return 0;
    auto scope = static_cast<FBTMCFetchScope *>(opaque);
    int status = scope->current->httpStatus.load();
    sObservation = scope->previous;
    delete scope;
    return status;
}

static NSString *FBTMCText(const std::string &s) {
    if (s.size() > 2 * 1024 * 1024) return @"<over_2mb_limit>";
    return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"<non_utf8>";
}

static void FBTMCAsyncFetch(const void *fetcher, const std::string &method,
        const std::string &purpose, const FBTMCRequestPairs &params,
        FBTMCCompletion completion, const std::string &routingHint, uint64_t target) {
    if (!sOriginalFetch) return;
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        sOriginalFetch(fetcher, method, purpose, params, std::move(completion), routingHint, target);
        return;
    }
    unsigned long long requestID = ++sRequests;
    NSString *requestLabel = FBTMCText(purpose);
    // Binary TigonRequest constructor and device logs prove argument 1 is the
    // HTTP method. Endpoint URL is constructed inside the fetcher, not passed here.
    NSString *requestMethod = FBTMCText(method);
    NSMutableDictionary *details = [@{@"request_id": @(requestID),
        @"request_method": requestMethod, @"capture_reason": requestLabel,
        @"request_metadata_source": @"native_fetcher_arguments",
        @"transport": @"FBMobileConfigTigonFetcher", @"request_param_count": @(params.size()),
        @"routing_hint_present": @(!routingHint.empty()),
        @"query_hash_source": @"native_request_parameter_pairs",
        @"query_hash_state": @"not_observed", @"one_query_hash_state": @"not_observed"} mutableCopy];
    NSMutableDictionary *parameterShape = [NSMutableDictionary dictionary];
    for (const auto &pair : params) {
        // Only public protocol field names are allowed; account/token values and
        // regex/name contents are never serialized. Booleans are useful for 400s.
        static const std::vector<std::string> allowed = {"api_version", "locale",
            "universe_regex", "param", "gatekeeper", "with_universe_params",
            "with_current_experiment_group", "with_only_current_experiment_group",
            "with_all_experiment_groups", "with_experiment_params",
            "with_experiment_universes", "with_gatekeepers", "needs_name", "skip_qe",
            "query_hash", "one_query_hash"};
        if (std::find(allowed.begin(), allowed.end(), pair.first) != allowed.end()) {
            NSString *key = FBTMCText(pair.first);
            if (pair.first == "needs_name" || pair.first == "skip_qe" || pair.first.find("with_") == 0) {
                BOOL valid = pair.second == "true" || pair.second == "false" || pair.second == "0" || pair.second == "1";
                parameterShape[key] = valid ? FBTMCText(pair.second) : @"unexpected_boolean_encoding";
            } else parameterShape[key] = [NSString stringWithFormat:@"%llu_bytes", (unsigned long long)pair.second.size()];
        }
        if (pair.first == "query_hash" || pair.first == "one_query_hash") {
            NSString *prefix = FBTMCText(pair.first);
            BOOL empty = pair.second.empty() || pair.second == "null" || pair.second == "none";
            details[[prefix stringByAppendingString:@"_state"]] = empty ? @"empty" : @"present";
            details[[prefix stringByAppendingString:@"_length"]] = @(pair.second.size());
        }
    }
    NSData *shapeJSON = [NSJSONSerialization dataWithJSONObject:parameterShape options:NSJSONWritingSortedKeys error:nil];
    details[@"request_parameter_summary"] = [[NSString alloc] initWithData:shapeJSON encoding:NSUTF8StringEncoding] ?: @"{}";
    FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_fetch_started", details);
    auto original = std::make_shared<FBTMCCompletion>(std::move(completion));
    NSDictionary *request = [details copy];
    CFTimeInterval started = CACurrentMediaTime();
    auto observation = purpose == "mobileconfig_qe_info" ? sObservation : nullptr;
    FBTMCCompletion wrapped = [original, request, requestLabel, requestMethod, started, observation]
            (bool success, const std::string &body) {
        ++sResponses;
        if (!success) ++sFailures;
        @try {
            NSMutableDictionary *response = [request mutableCopy];
            response[@"native_transport_success"] = @(success);
            response[@"response_bytes"] = @(body.size());
            response[@"duration_ms"] = @((CACurrentMediaTime() - started) * 1000.0);
            response[@"payload_provenance"] = success ? @"native_decoded_completion" : @"native_formatted_transport_error";
            if (!success) {
                response[@"message"] = FBTMCText(body);
                // This callback contains Tigon's formatted error, not the HTTP body.
                const std::string marker = "domain: FBHTTPErrorDomain code: ";
                size_t at = body.find(marker);
                if (at != std::string::npos) {
                    at += marker.size();
                    if (at + 3 <= body.size() && body[at] >= '1' && body[at] <= '5' &&
                        body[at+1] >= '0' && body[at+1] <= '9' && body[at+2] >= '0' && body[at+2] <= '9' &&
                        (at+3 == body.size() || body[at+3] == ' ')) {
                        response[@"http_status"] = @((body[at]-'0')*100 + (body[at+1]-'0')*10 + body[at+2]-'0');
                        response[@"http_status_source"] = @"native_formatted_transport_error";
                        if (observation) observation->httpStatus.store([response[@"http_status"] intValue]);
                    }
                }
            }
            FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_fetch_completed", response);
            if (success && body.size() <= 2 * 1024 * 1024) {
                NSData *data = [NSData dataWithBytes:body.data() length:body.size()];
                FBTMobileConfigResponseCaptureWriteRawBody(data, @"", @"", requestMethod, response,
                    requestLabel, 0, @"", @"FBMobileConfigTigonFetcher");
            }
        } @catch (__unused NSException *exception) {
            FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_capture_exception", @{});
        }
        // Native callback receives exactly the original status and bytes.
        if (original && *original) (*original)(success, body);
    };
    sOriginalFetch(fetcher, method, purpose, params, std::move(wrapped), routingHint, target);
}

void FBTMobileConfigFetcherCaptureInstall(void) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled] || sFetcherInstalled) return;
    static const unsigned char uuid[16] = {76,76,68,254,85,85,49,68,161,194,108,202,228,237,37,151};
    NSString *failure = nil;
    sFetcherInstalled = FBTRebindVerifiedImageConstSlot("FBSharedFramework", 0x8161f88ULL,
        uuid, 0xa17f70ULL, (void *)FBTMCAsyncFetch, (void **)&sOriginalFetch, &failure);
    sFetcherFailure = [failure copy];
    FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_fetcher_hook", @{
        @"hook_installed": @(sFetcherInstalled), @"message": sFetcherFailure ?: @"",
        @"capture_surface": @"UUID-verified FBMobileConfigTigonFetcher asyncFetch data slot; native decoded completion"});
}

NSDictionary *FBTMobileConfigFetcherCaptureStatus(void) {
    return @{@"native_mc_fetcher_installed": @(sFetcherInstalled),
        @"native_mc_fetcher_failure": sFetcherFailure ?: @"not_attempted",
        @"native_mc_requests": @(sRequests.load()), @"native_mc_responses": @(sResponses.load()),
        @"native_mc_failures": @(sFailures.load())};
}
