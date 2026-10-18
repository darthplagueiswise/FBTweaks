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
#include <cstring>
#include <mutex>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach/mach.h>
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

// Read-only observations; no tokens, IDs, request mutations or forced results.
// Layout and selectors are enabled only after the existing UUID/slot check.
struct FBTMCBoolParam { uint64_t value; };
static_assert(sizeof(FBTMCBoolParam) == 8, "mc_bool_param_t ABI mismatch");
using FBTMCStartupBoolFn = bool (*)(id, SEL, FBTMCBoolParam, bool);
static FBTMCStartupBoolFn sOriginalStartupBool;
static BOOL sAuthReadHookInstalled;
static NSString *sAuthReadHookFailure;
static std::mutex sAuthReadMutex;
struct FBTMCAuthRead { unsigned long long count = 0; bool value = false; };
static FBTMCAuthRead sSessionAuthRead, sLoggedOutAuthRead;

static uintptr_t FBTMCSharedRVA(const void *address) {
    Dl_info info = {};
    if (!address || !dladdr(address, &info) || !info.dli_fname || !info.dli_fbase) return 0;
    const char *base = strrchr(info.dli_fname, '/');
    if (strcmp(base ? base + 1 : info.dli_fname, "FBSharedFramework") != 0) return 0;
    return (uintptr_t)address - (uintptr_t)info.dli_fbase;
}

static void FBTMCObserveAuthRead(uint64_t specifier, uintptr_t callerRVA, bool result) {
    if (specifier != 0x00810cc7000042acULL) return;
    std::lock_guard<std::mutex> guard(sAuthReadMutex);
    // Exact return sites: session constructor and logged-out constructor.
    // A UI inspection of the same flag is NOT evidence of consumption here.
    FBTMCAuthRead *read = callerRVA == 0x53cc5c ? &sSessionAuthRead :
                          callerRVA == 0x446c7c ? &sLoggedOutAuthRead : nullptr;
    if (read) { ++read->count; read->value = result; }
}

static bool FBTMCStartupBool(id object, SEL command, FBTMCBoolParam param, bool fallback) {
    const void *caller = __builtin_return_address(0);
    bool result = sOriginalStartupBool(object, command, param, fallback);
    if (param.value == 0x00810cc7000042acULL &&
            [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        FBTMCObserveAuthRead(param.value, FBTMCSharedRVA(caller), result);
    }
    return result;
}

static NSDictionary *FBTMCAuthReadSnapshot(void) {
    std::lock_guard<std::mutex> guard(sAuthReadMutex);
    NSMutableDictionary *state = [@{@"hook_installed": @(sAuthReadHookInstalled),
        @"scope": @"process_constructor_reads_not_request_identity",
        @"session_read_count": @(sSessionAuthRead.count),
        @"logged_out_read_count": @(sLoggedOutAuthRead.count),
        @"session_state": sSessionAuthRead.count ? @"observed" : @"not_observed",
        @"logged_out_state": sLoggedOutAuthRead.count ? @"observed" : @"not_observed"} mutableCopy];
    if (sSessionAuthRead.count) state[@"session_last_value"] = @(sSessionAuthRead.value);
    if (sLoggedOutAuthRead.count) state[@"logged_out_last_value"] = @(sLoggedOutAuthRead.value);
    return state;
}

static void FBTMCInstallAuthReadHook(void) {
    if (!sFetcherInstalled || sAuthReadHookInstalled) return;
    Class cls = NSClassFromString(@"FBMobileConfigStartupConfigs");
    if (!cls) { sAuthReadHookFailure = @"class_not_loaded"; return; }
    @synchronized (cls) {
        if (sAuthReadHookInstalled) return;
        Method method = class_getInstanceMethod(cls, sel_registerName("getBool:withDefault:"));
        const char *encoding = method ? method_getTypeEncoding(method) : nullptr;
        IMP original = method ? method_getImplementation(method) : nullptr;
        if (!encoding || strcmp(encoding, "B28@0:8{mc_bool_param_t=Q}16B24") != 0 ||
                FBTMCSharedRVA((const void *)original) != 0x15b9f4) {
            sAuthReadHookFailure = @"method_ABI_or_original_IMP_mismatch"; return;
        }
        sOriginalStartupBool = (FBTMCStartupBoolFn)original;
        method_setImplementation(method, (IMP)FBTMCStartupBool);
        sAuthReadHookInstalled = YES;
        sAuthReadHookFailure = nil;
    }
}

static bool FBTMCReadWord(uintptr_t address, uintptr_t *value) {
    if (!address || !value) return false;
    static_assert(sizeof(vm_address_t) >= sizeof(uintptr_t), "VM address must preserve native pointers");
    vm_size_t size = 0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)address,
        sizeof(*value), (vm_address_t)value, &size) == KERN_SUCCESS && size == sizeof(*value);
}

static NSDictionary *FBTMCServiceSnapshot(const void *fetcher, BOOL verifiedLayout) {
    if (!verifiedLayout) return @{@"state": @"layout_not_verified"};
    uintptr_t object = (uintptr_t)fetcher, service = 0, vtable = 0, send = 0;
    if (!object || object > UINTPTR_MAX - 0x50 || !FBTMCReadWord(object + 0x50, &service))
        return @{@"state": @"fetcher_unreadable"};
    if (!service) return @{@"state": @"service_null"};
    if (!FBTMCReadWord(service, &vtable) || !vtable || vtable > UINTPTR_MAX - 0x10 ||
            !FBTMCReadWord(vtable + 0x10, &send)) return @{@"state": @"service_unreadable"};
    uintptr_t rva = FBTMCSharedRVA((const void *)send);
    NSMutableDictionary *state = [@{@"state": @"observed",
        @"dispatch": rva == 0x45be80 ? @"TigonStack::sendRequest" : @"other_or_unresolved",
        @"source": @"verified_fetcher_plus_0x50_vtable_plus_0x10",
        @"auth_header_state": @"not_observed"} mutableCopy];
    if (rva) state[@"shared_send_rva"] = [NSString stringWithFormat:@"0x%llx", (unsigned long long)rva];
    // Raw pointers and account/token data are deliberately never emitted.
    return state;
}

static NSString *FBTMCDiagnosticJSON(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

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
            "with_experiment_universes", "with_gatekeepers", "with_experiments", "with_params",
            "with_groups", "with_group_params", "needs_name", "skip_qe",
            "query_hash", "one_query_hash"};
        if (pair.first == "device_id") parameterShape[@"device_id_present"] = @(!pair.second.empty());
        if (pair.first == "queries") {
            NSString *queries = FBTMCText(pair.second);
            NSData *raw = [queries dataUsingEncoding:NSUTF8StringEncoding];
            id parsed = raw ? [NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingFragmentsAllowed error:nil] : nil;
            parameterShape[@"queries_is_array"] = @([parsed isKindOfClass:NSArray.class]);
            if ([parsed isKindOfClass:NSArray.class]) parameterShape[@"queries_count"] = @([parsed count]);
        }
        if (std::find(allowed.begin(), allowed.end(), pair.first) != allowed.end()) {
            NSString *key = FBTMCText(pair.first);
            if (pair.first == "needs_name" || pair.first == "skip_qe" || pair.first.find("with_") == 0) {
                BOOL valid = pair.second == "true" || pair.second == "false" || pair.second == "0" || pair.second == "1";
                parameterShape[key] = valid ? FBTMCText(pair.second) : @"unexpected_boolean_encoding";
            } else if (pair.first == "api_version" && !pair.second.empty() && pair.second.size() <= 5 &&
                       pair.second.find_first_not_of("0123456789") == std::string::npos) {
                parameterShape[key] = FBTMCText(pair.second);
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
    details[@"tigon_service_snapshot"] = FBTMCDiagnosticJSON(FBTMCServiceSnapshot(fetcher, sFetcherInstalled));
    details[@"auth_validation_read_snapshot"] = FBTMCDiagnosticJSON(FBTMCAuthReadSnapshot());
    FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_fetch_started", details);
    FBTMobileConfigTigonCaptureExpectRequest(details);
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
            NSDictionary *nativeResponse = FBTMobileConfigTigonCaptureObserveNativeCompletion(response, success);
            for (NSString *key in @[@"native_tigon_correlation", @"http_status", @"http_status_source", @"response_body_bytes", @"request_host", @"request_path"]) {
                if (nativeResponse[key]) response[key] = nativeResponse[key];
            }
            if (observation && response[@"http_status"]) observation->httpStatus.store([response[@"http_status"] intValue]);
            FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_fetch_completed", response);
            // The terminal observer already persisted/diagnosed these exact bytes.
            // Avoid duplicate files and an artificial HTTP=0 event after HTTP=200.
            BOOL capturedAtTerminal = [nativeResponse[@"response_body_bytes"] unsignedIntegerValue] > 0 &&
                [nativeResponse[@"native_tigon_correlation"] hasPrefix:@"native_mc_completion_inside_simple_"];
            if (success && !capturedAtTerminal && body.size() <= 2 * 1024 * 1024) {
                NSData *data = [NSData dataWithBytes:body.data() length:body.size()];
                FBTMobileConfigResponseCaptureWriteRawBody(data, @"", @"", requestMethod, response,
                    requestLabel, [response[@"http_status"] integerValue], @"", @"FBMobileConfigTigonFetcher");
            }
        } @catch (__unused NSException *exception) {
            FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_capture_exception", @{});
        }
        FBTMobileConfigTigonCaptureCompleteRequest(request[@"request_id"]);
        // Native callback receives exactly the original status and bytes.
        if (original && *original) (*original)(success, body);
    };
    try { sOriginalFetch(fetcher, method, purpose, params, std::move(wrapped), routingHint, target); }
    catch (...) { FBTMobileConfigTigonCaptureCompleteRequest(request[@"request_id"]); throw; }
}

void FBTMobileConfigFetcherCaptureInstall(void) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    if (sFetcherInstalled) { FBTMCInstallAuthReadHook(); return; }
    static const unsigned char uuid[16] = {76,76,68,254,85,85,49,68,161,194,108,202,228,237,37,151};
    NSString *failure = nil;
    sFetcherInstalled = FBTRebindVerifiedImageConstSlot("FBSharedFramework", 0x8161f88ULL,
        uuid, 0xa17f70ULL, (void *)FBTMCAsyncFetch, (void **)&sOriginalFetch, &failure);
    sFetcherFailure = [failure copy];
    FBTMCInstallAuthReadHook();
    FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_fetcher_hook", @{
        @"hook_installed": @(sFetcherInstalled), @"message": sFetcherFailure ?: @"",
        @"capture_surface": @"UUID-verified FBMobileConfigTigonFetcher asyncFetch data slot; native decoded completion"});
}

NSDictionary *FBTMobileConfigFetcherCaptureStatus(void) {
    return @{@"native_mc_fetcher_installed": @(sFetcherInstalled),
        @"auth_validation_reads": FBTMCAuthReadSnapshot(),
        @"auth_validation_read_hook_failure": sAuthReadHookFailure ?: @"none_or_not_attempted",
        @"native_mc_fetcher_failure": sFetcherFailure ?: @"not_attempted",
        @"native_mc_requests": @(sRequests.load()), @"native_mc_responses": @(sResponses.load()),
        @"native_mc_failures": @(sFailures.load())};
}



