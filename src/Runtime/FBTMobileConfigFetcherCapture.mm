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

static NSString *FBTMCText(const std::string &s) {
    if (s.size() > 2 * 1024 * 1024) return @"<over_2mb_limit>";
    return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"<non_utf8>";
}

static void FBTMCAsyncFetch(const void *fetcher, const std::string &url,
        const std::string &purpose, const FBTMCRequestPairs &params,
        FBTMCCompletion completion, const std::string &account, uint64_t target) {
    if (!sOriginalFetch) return;
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        sOriginalFetch(fetcher, url, purpose, params, std::move(completion), account, target);
        return;
    }
    unsigned long long requestID = ++sRequests;
    NSString *requestLabel = FBTMCText(purpose);
    NSURLComponents *components = [NSURLComponents componentsWithString:FBTMCText(url)];
    NSString *host = components.host ?: @"";
    NSString *path = components.path ?: @"";
    NSMutableDictionary *details = [@{@"request_id": @(requestID),
        @"request_host": host, @"request_path": path, @"capture_reason": requestLabel,
        @"transport": @"FBMobileConfigTigonFetcher", @"request_param_count": @(params.size()),
        @"account_argument_present": @(!account.empty()),
        @"query_hash_source": @"native_request_parameter_pairs",
        @"query_hash_state": @"not_observed", @"one_query_hash_state": @"not_observed"} mutableCopy];
    for (const auto &pair : params) {
        if (pair.first == "query_hash" || pair.first == "one_query_hash") {
            NSString *prefix = FBTMCText(pair.first);
            BOOL empty = pair.second.empty() || pair.second == "null" || pair.second == "none";
            details[[prefix stringByAppendingString:@"_state"]] = empty ? @"empty" : @"present";
            details[[prefix stringByAppendingString:@"_length"]] = @(pair.second.size());
        }
    }
    FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_fetch_started", details);
    auto original = std::make_shared<FBTMCCompletion>(std::move(completion));
    NSDictionary *request = [details copy];
    CFTimeInterval started = CACurrentMediaTime();
    FBTMCCompletion wrapped = [original, request, requestLabel, host, path, started]
            (bool success, const std::string &body) {
        ++sResponses;
        if (!success) ++sFailures;
        @try {
            NSMutableDictionary *response = [request mutableCopy];
            response[@"native_transport_success"] = @(success);
            response[@"response_bytes"] = @(body.size());
            response[@"duration_ms"] = @((CACurrentMediaTime() - started) * 1000.0);
            if (!success) response[@"message"] = FBTMCText(body);
            FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_fetch_completed", response);
            if (body.size() <= 2 * 1024 * 1024) {
                NSData *data = [NSData dataWithBytes:body.data() length:body.size()];
                FBTMobileConfigResponseCaptureWriteRawBody(data, host, path, @"", request,
                    requestLabel, 0, @"", @"FBMobileConfigTigonFetcher");
            }
        } @catch (__unused NSException *exception) {
            FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_capture_exception", @{});
        }
        // Native callback receives exactly the original status and bytes.
        if (original && *original) (*original)(success, body);
    };
    sOriginalFetch(fetcher, url, purpose, params, std::move(wrapped), account, target);
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
