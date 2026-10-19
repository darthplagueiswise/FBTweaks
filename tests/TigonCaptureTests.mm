#import <Foundation/Foundation.h>
#include <cstring>
#import "../src/Runtime/FBTNamesResponseSummary.m"
#import "../src/Runtime/FBTMobileConfigTigonCapture.mm"
#import "../src/Runtime/FBTMobileConfigFetcherCapture.mm"

NSString * const FBTKeyMobileConfigFetchDiagnosticsEnabled = @"test.capture";
NSString * const FBTKeyEmployeeEnabled = @"test.employee";
static BOOL sEnabled = YES;
void FBTEmployeeObserveMCBool(uint64_t, BOOL, BOOL, const void *) {}
BOOL FBTEmployeeApplyTWProbe(uint64_t, BOOL value) { return value; }
NSDictionary *FBTEmployeeDiagnosticsSnapshot(void) { return @{@"sequence": @0, @"tw_probe_armed": @NO}; }
@implementation FBTDefaults
+ (BOOL)boolForKey:(NSString *)key { return sEnabled; }
@end

static NSMutableArray *sSaved, *sEvents;
static NSDictionary *sLastNativeEvent;
static NSDictionary *sLastTransportEvent;
static NSUInteger sBodyCalls, sResponseCalls, sEndCalls;
static void *sExpectedBodyArgument, *sExpectedResponse, *sExpectedSummary;
static void Check(BOOL result, NSString *message) { if (!result) { NSLog(@"FAIL: %@", message); exit(1); } }
void FBTMobileConfigFetchDiagnosticsRecord(NSString *event, NSDictionary *details) { [sEvents addObject:event]; if ([event isEqual:@"native_mc_fetch_completed"]) sLastNativeEvent = [details copy]; }
void FBTMobileConfigResponseCaptureRecordTransportEvent(NSString *event, NSDictionary *details) { [sEvents addObject:event]; sLastTransportEvent = [details copy]; }
NSDictionary *FBTMobileConfigResponseCaptureArmInfo(void) { return @{}; }
BOOL FBTMobileConfigResponseCaptureShouldCaptureRequest(NSString *, NSString *, NSString *) { return YES; }
void FBTMobileConfigResponseCaptureWriteRawBody(NSData *data, NSString *, NSString *, NSString *, NSDictionary *state,
        NSString *, NSInteger status, NSString *, NSString *) {
    if (!sEnabled) return;
    [sSaved addObject:@{@"data": [data copy], @"status": @(status), @"request_id": state[@"request_id"] ?: @0, @"provenance": state[@"payload_provenance"] ?: @""}];
}
BOOL FBTRebindVerifiedMainConstSlot(uint64_t, const unsigned char *, const char *, void *, void **, NSString **) { return NO; }
BOOL FBTRebindVerifiedImageConstSlot(const char *, uint64_t, const unsigned char *, uint64_t, void *, void **, NSString **) { return NO; }
int rebind_symbols(struct rebinding[], size_t) { return 0; }

struct TestRequest { std::string host, path, method, query; };
static const void *URL(const void *r) { return r; }
static const std::string &Host(const void *r) { return ((const TestRequest *)r)->host; }
static const std::string &Path(const void *r) { return ((const TestRequest *)r)->path; }
static const std::string &RequestMethod(const void *r) { return ((const TestRequest *)r)->method; }
static const std::string &Query(const void *r) { return ((const TestRequest *)r)->query; }
static FBTHeaderResult TestHeader(const void *, const std::string &key) {
    FBTHeaderResult result = {};
    if (key == "Authorization") {
        new (result.bytes) std::string("OAuth fixture-secret"); result.bytes[24] = 1;
    }
    return result;
}
static void ResponseOriginal(void *, void *r) {
    Check(r == sExpectedResponse, @"response forwarded unchanged"); ++sResponseCalls;
}
static void BodyOriginal(void *, void *b) {
    Check(b == sExpectedBodyArgument && *(void **)b != nullptr, @"body ownership preserved until original");
    *(void **)b = nullptr; ++sBodyCalls;
}
static void EndOriginal(void *, void *summary) {
    Check(summary == sExpectedSummary, @"summary forwarded unchanged");
    ++sEndCalls;
}
static NSUInteger sNativeCalls, sCompletionCalls;
static std::string sNativeBody;
static void NativeOriginal(const void *, const std::string &method, const std::string &purpose,
        const FBTMCRequestPairs &params, FBTMCCompletion completion, const std::string &hint, uint64_t target) {
    Check(method == "POST" && purpose == "mobileconfig_qe_info" && hint.empty() && target == 0,
        @"native fetcher arguments forwarded unchanged");
    Check(params.size() == 2, @"native request parameters preserved");
    ++sNativeCalls; completion(false, sNativeBody);
}
static FBTMCCompletion sDeferredCompletion;
static void DeferredOriginal(const void *, const std::string &, const std::string &,
        const FBTMCRequestPairs &, FBTMCCompletion completion, const std::string &, uint64_t) {
    sDeferredCompletion = std::move(completion);
}
static FBTMCRequestPairs sExperimentNativeParams;
static void ExperimentOriginal(const void *, const std::string &, const std::string &,
        const FBTMCRequestPairs &params, FBTMCCompletion completion, const std::string &, uint64_t) {
    sExperimentNativeParams = params;
    completion(false, sNativeBody);
}
static void CompletionFromNativeEOM(void *, void *summary) {
    Check(summary == sExpectedSummary, @"EOM summary preserved without onStarted");
    sDeferredCompletion(false, sNativeBody);
}
static void CompletionFromNativeError(void *, const void *, void *summary) {
    Check(summary == sExpectedSummary, @"onError summary forwarded unchanged");
    sDeferredCompletion(false, sNativeBody);
}
static const std::string sSuccessBody = "{\"id_to_names\":[\"1:test:0:flag\"]}";
static void SuccessFromNativeEOM(void *, void *) { sDeferredCompletion(true, sSuccessBody); }
static NSUInteger sStartupCalls;
static bool StartupOriginal(id object, SEL command, FBTMCBoolParam param, bool fallback) {
    Check(object == nil && command == sel_registerName("getBool:withDefault:") &&
          param.value == 0x00810cc7000042acULL, @"startup getter ABI and arguments preserved");
    ++sStartupCalls; return !fallback;
}
int main(void) { @autoreleasepool {
    sSaved = [NSMutableArray array]; sEvents = [NSMutableArray array];
    Check([FBTAuthorizationSummary("OAuth fixture-secret")[@"authorization_scheme"] isEqual:@"OAuth"], @"OAuth scheme observed");
    Check(![FBTAuthorizationSummary("Bearer ")[@"authorization_credential_present"] boolValue], @"empty credential is not present");
    Check(![FBTAuthorizationSummary("OAuth fixture-secret").description containsString:@"fixture-secret"], @"secret never enters summary");
    Check([FBTObserveRequestAuthorization((void *)1)[@"authorization_state"] isEqual:@"not_observed"], @"unverified getter is unknown");
    sFindHeader = TestHeader;
    Check([FBTObserveRequestAuthorization((void *)1)[@"authorization_scheme"] isEqual:@"OAuth"], @"native optional header ABI exercised");
    sFindHeader = nullptr;
    NSDictionary *probe = FBTMCAuthReadSnapshot();
    Check([probe[@"session_state"] isEqual:@"not_observed"] && !probe[@"session_last_value"],
        @"unobserved auth selection is not false");
    FBTMCObserveAuthRead(0x00810cc7000042acULL, 0x123, true);
    FBTMCObserveAuthRead(0, 0x53cc5c, true);
    Check([FBTMCAuthReadSnapshot()[@"session_read_count"] intValue] == 0,
        @"UI reads and other parameters cannot masquerade as constructor consumption");
    FBTMCObserveAuthRead(0x00810cc7000042acULL, 0x53cc5c, false);
    FBTMCObserveAuthRead(0x00810cc7000042acULL, 0x446c7c, true);
    probe = FBTMCAuthReadSnapshot();
    Check([probe[@"session_state"] isEqual:@"observed"] && ![probe[@"session_last_value"] boolValue] &&
          [probe[@"logged_out_last_value"] boolValue], @"session and logged-out observations remain separate");
    sOriginalStartupBool = StartupOriginal;
    Check(FBTMCStartupBool(nil, sel_registerName("getBool:withDefault:"), {0x00810cc7000042acULL}, false) &&
          !FBTMCStartupBool(nil, sel_registerName("getBool:withDefault:"), {0x00810cc7000042acULL}, true) &&
          sStartupCalls == 2, @"startup original called once per request and result preserved");
    Check([FBTMCServiceSnapshot((void *)1, NO)[@"state"] isEqual:@"layout_not_verified"],
        @"unverified layout is never read");
    Check([FBTMCServiceSnapshot((void *)1, YES)[@"state"] isEqual:@"fetcher_unreadable"],
        @"unmapped fetcher does not crash");
    uintptr_t fakeFetcher[12] = {}, fakeVtable[3] = {0, 0, (uintptr_t)StartupOriginal};
    uintptr_t fakeService = (uintptr_t)fakeVtable;
    Check([FBTMCServiceSnapshot(fakeFetcher, YES)[@"state"] isEqual:@"service_null"], @"null service identified");
    fakeFetcher[10] = 1;
    Check([FBTMCServiceSnapshot(fakeFetcher, YES)[@"state"] isEqual:@"service_unreadable"],
        @"unmapped service does not crash");
    fakeFetcher[10] = (uintptr_t)&fakeService;
    probe = FBTMCServiceSnapshot(fakeFetcher, YES);
    Check([probe[@"state"] isEqual:@"observed"] && [probe[@"dispatch"] isEqual:@"other_or_unresolved"] &&
          [probe[@"auth_header_state"] isEqual:@"not_observed"] && !probe[@"shared_send_rva"],
        @"unknown implementation never claimed as native TigonStack or authenticated");
    sTigonCaptureLock = [NSLock new]; sTigonCapturedRequests = [NSMutableDictionary dictionary];
    sTigonRequestURL = URL; sTigonURLHost = Host; sTigonURLPath = Path; sTigonURLQuery = Query; sTigonRequestMethod = RequestMethod;
    sSimpleBody = BodyOriginal; sSimpleResponse = ResponseOriginal; sSimpleEOM = EndOriginal;
    int object = 0, summary = 0; TestRequest request = {"graph.facebook.com", "/method/mobileconfig_qe_info", "POST", ""};
    FBTSimpleOnStarted(&object, &request);
    uint16_t status = 400; sExpectedResponse = &status; FBTSimpleOnResponse(&object, &status);
    const uint8_t a[] = {'{','"','e','"',':','"'}, b[] = {'x','"','}'};
    FBTFollyIOBufLayout first = {}, second = {}; first.length = sizeof(a); first.data = a; first.next = &second;
    second.length = sizeof(b); second.data = b; second.next = &first;
    void *head = &first; sExpectedBodyArgument = &head; FBTSimpleOnBody(&object, &head);
    Check(head == nullptr && sBodyCalls == 1, @"original consumes unique_ptr exactly once");
    sExpectedSummary = &summary; FBTSimpleOnEOM(&object, &summary);
    Check(sResponseCalls == 1 && sEndCalls == 1, @"response and EOM forwarded once");
    Check([sSaved[0][@"status"] integerValue] == 400 && [sSaved[0][@"data"] isEqual:[@"{\"e\":\"x\"}" dataUsingEncoding:NSUTF8StringEncoding]], @"actual 400 status and chained body retained");
    Check([sSaved[0][@"provenance"] isEqual:@"http_response_body_before_native_status_conversion"], @"body provenance explicit");
    Check(sTigonCapturedRequests.count == 0, @"EOM clears context");
    request.path = "/api/unrelated"; FBTSimpleOnStarted(&object, &request);
    Check(sTigonCapturedRequests.count == 0, @"unrelated shared callbacks ignored");
    request.path = "/method/mobileconfig"; FBTSimpleOnStarted(&object, &request);
    sEnabled = NO; FBTTigonFinishCapture(&object);
    Check(sSaved.count == 1 && sTigonCapturedRequests.count == 0, @"logging disabled before completion prevents late persistence");
    BOOL tooLarge = NO, invalid = NO; first.length = 2 * 1024 * 1024 + 1;
    Check(FBTCopyIOBufChain(&first, &tooLarge, &invalid) == nil && tooLarge, @"oversized chain rejected before dereference");
    first.length = 1; first.data = nullptr;
    Check(FBTCopyIOBufChain(&first, &tooLarge, &invalid) == nil && invalid, @"invalid chain rejected");
    sEnabled = YES; sOriginalFetch = NativeOriginal;
    sNativeBody = "None domain: FBHTTPErrorDomain code: 400 detail: ";
    FBTMCRequestPairs params = {{"needs_name", "1"}, {"access_token", "never_persist_this"}};
    auto completion = [](bool success, const std::string &body) {
        Check(!success && body == sNativeBody, @"native failure status and bytes forwarded unchanged"); ++sCompletionCalls;
    };
    void *scope = FBTMobileConfigFetcherCaptureBeginScope();
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    Check(FBTMobileConfigFetcherCaptureCurrentHTTPStatus() == 400, @"HTTP rejection belongs to active selection scope");
    void *nested = FBTMobileConfigFetcherCaptureBeginScope();
    Check(FBTMobileConfigFetcherCaptureCurrentHTTPStatus() == 0 && FBTMobileConfigFetcherCaptureEndScope(nested) == 0 &&
        FBTMobileConfigFetcherCaptureCurrentHTTPStatus() == 400, @"nested scope cannot inherit unrelated rejection");
    Check(FBTMobileConfigFetcherCaptureEndScope(scope) == 400 && FBTMobileConfigFetcherCaptureCurrentHTTPStatus() == 0, @"scope result retained and thread state cleared");
    Check(sNativeCalls == 1 && sCompletionCalls == 1 && sSaved.count == 1, @"formatted failure is not persisted as an HTTP body");
    Check([sLastNativeEvent[@"http_status"] integerValue] == 400 && [sLastNativeEvent[@"request_method"] isEqual:@"POST"] &&
        sLastNativeEvent[@"request_path"] == nil, @"failure status parsed and method not mislabelled as URL");
    Check([sLastNativeEvent[@"request_parameter_summary"] rangeOfString:@"access_token"].location == NSNotFound &&
        [sLastNativeEvent[@"request_parameter_summary"] rangeOfString:@"never_persist_this"].location == NSNotFound,
        @"credential fields excluded from metadata");
    sEnabled = NO;
    Check(FBTMCStartupBool(nil, sel_registerName("getBool:withDefault:"), {0x00810cc7000042acULL}, false) &&
        sStartupCalls == 3, @"logging off still forwards startup getter unchanged");
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    Check(sNativeCalls == 2 && sCompletionCalls == 2, @"logging off forwards native fetch directly");
    sEnabled = YES; sOriginalFetch = DeferredOriginal;
    void *lateScope = FBTMobileConfigFetcherCaptureBeginScope();
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    Check(FBTMobileConfigFetcherCaptureEndScope(lateScope) == 0, @"pending request has no invented status");
    sDeferredCompletion(false, sNativeBody); sDeferredCompletion = nullptr;
    Check(sCompletionCalls == 3 && FBTMobileConfigFetcherCaptureCurrentHTTPStatus() == 0,
        @"late callback owns observation safely and cannot contaminate another selection");
    // Reproduce the device path: EOM/native MC completion arrive with no
    // onStarted context. Native error conversion still retains the IOBuf.
    first.length = sizeof(a); first.data = a;
    alignas(8) uint8_t nativeState[0x88] = {};
    uint16_t errorStatus = 400; memcpy(nativeState + 0x48, &errorStatus, sizeof(errorStatus));
    void *retainedBody = &first; memcpy(nativeState + 0x80, &retainedBody, sizeof(retainedBody));
    NSUInteger before = sSaved.count;
    sOriginalFetch = DeferredOriginal;
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    sSimpleEOM = CompletionFromNativeEOM;
    FBTSimpleOnEOM(nativeState, &summary); sDeferredCompletion = nullptr;
    Check(sSaved.count == before + 1 && [sSaved.lastObject[@"status"] integerValue] == 400 &&
        [sSaved.lastObject[@"data"] isEqual:[@"{\"e\":\"x\"}" dataUsingEncoding:NSUTF8StringEncoding]],
        @"HTTP body recovered when onStarted is absent");
    Check([sLastNativeEvent[@"native_tigon_correlation"] isEqual:@"native_mc_completion_inside_simple_eom"],
        @"native completion establishes exact correlation");
    void *unchanged = nullptr; memcpy(&unchanged, nativeState + 0x80, sizeof(unchanged));
    Check(unchanged == retainedBody && sCurrentSimpleEnd == nullptr, @"retained body ownership and TLS restored");
    Check([FBTMobileConfigTigonCaptureObserveNativeCompletion(@{}, NO)[@"native_tigon_correlation"] isEqual:@"no_simple_terminal_scope"],
        @"unrelated completion cannot reuse a previous native response");
    // onResponse/onBody precede native identification; no onStarted is needed.
    before = sSaved.count;
    memset(nativeState, 0, sizeof(nativeState));
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    Check(sPendingNativeRequests.count == 1, @"native request authorizes provisional copying");
    request.path = "/method";
    FBTSimpleOnStarted(nativeState, &request);
    Check(![FBTTigonContextForObject(nativeState)[@"mc_correlated"] boolValue], @"generic API URL remains provisional until native identity is confirmed");
    first.length = sizeof(a); first.data = a; first.next = &second;
    sExpectedResponse = &status;
    FBTSimpleOnResponse(nativeState, &status);
    head = &first; sExpectedBodyArgument = &head;
    FBTSimpleOnBody(nativeState, &head);
    Check(head == nullptr && sSaved.count == before, @"unconfirmed body stays in memory and native ownership is preserved");
    sSimpleError = CompletionFromNativeError;
    FBTSimpleOnError(nativeState, nullptr, &summary); sDeferredCompletion = nullptr;
    Check(sSaved.count == before + 1 && [sSaved.lastObject[@"data"] isEqual:[@"{\"e\":\"x\"}" dataUsingEncoding:NSUTF8StringEncoding]],
        @"partial response bytes survive onError without onStarted");
    Check([sSaved.lastObject[@"request_id"] isEqual:sLastNativeEvent[@"request_id"]] && sPendingNativeRequests.count == 0,
        @"promoted body has exact native request ID and pending request is cleared");
    Check([sLastNativeEvent[@"native_tigon_correlation"] isEqual:@"native_mc_completion_inside_simple_error"] && sCurrentSimpleEnd == nullptr,
        @"onError correlation is scoped and restored");
    Check([sLastNativeEvent[@"request_host"] isEqual:@"graph.facebook.com"] && [sLastNativeEvent[@"request_path"] isEqual:@"/method"],
        @"generic route metadata promoted only for the matched native MC completion");
    // An unrelated callback during a pending MC request must never be persisted.
    before = sSaved.count;
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    FBTSimpleOnResponse(&object, &status);
    head = &first; sExpectedBodyArgument = &head; FBTSimpleOnBody(&object, &head);
    sSimpleEOM = EndOriginal; FBTSimpleOnEOM(&object, &summary);
    Check(sSaved.count == before && FBTTigonContextForObject(&object) == nil, @"unrelated provisional body discarded at terminal callback");
    // The real MC error without bytes remains explicitly unavailable.
    FBTSimpleOnError(nativeState, nullptr, &summary); sDeferredCompletion = nullptr;
    Check(sSaved.count == before && [sLastTransportEvent[@"body_capture_status"] isEqual:@"not_delivered_to_observed_callback"],
        @"missing HTTP body is explicit and never replaced with native error text");
    // Broken null-ended chains must not be accepted as complete bodies.
    first.length = 0; first.next = nullptr;
    Check(FBTCopyIOBufChain(&first, &tooLarge, &invalid) == nil && invalid, @"null-ended IOBuf chain rejected");
    before = sSaved.count;
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params,
        [](bool ok, const std::string &body) { Check(ok && body == sSuccessBody, @"successful native completion forwarded unchanged"); }, "", 0);
    memset(nativeState, 0, sizeof(nativeState));
    uint16_t okStatus = 200; memcpy(nativeState + 0x48, &okStatus, sizeof(okStatus));
    sExpectedResponse = &okStatus; FBTSimpleOnResponse(nativeState, &okStatus);
    first.length = sSuccessBody.size(); first.data = (const uint8_t *)sSuccessBody.data(); first.next = &first;
    head = &first; sExpectedBodyArgument = &head; FBTSimpleOnBody(nativeState, &head);
    sSimpleEOM = SuccessFromNativeEOM; FBTSimpleOnEOM(nativeState, &summary); sDeferredCompletion = nullptr;
    Check(sSaved.count == before + 1 && [sSaved.lastObject[@"status"] intValue] == 200,
        @"successful response saved once with HTTP 200 instead of a duplicate HTTP 0");
    sEnabled = NO;
    Check(FBTMobileConfigTigonCaptureObserveNativeCompletion(@{}, NO).count == 0, @"logging off disables native correlation");
    sEnabled = YES; sOriginalFetch = ExperimentOriginal;
    FBTMobileConfigArmEmployeeExperiment(YES);
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    Check(sExperimentNativeParams.size() == params.size()+1 && params.size() == 2 &&
        sExperimentNativeParams.back() == FBTMCRequestPairs::value_type("is_employee", "true"), @"B adds one field to outgoing copy only");
    Check([sLastNativeEvent[@"experiment_profile"] isEqual:@"B_is_employee_true"] &&
        [sLastNativeEvent[@"employee_field_added"] boolValue] && ![sLastNativeEvent[@"native_transport_success"] boolValue],
        @"B profile retained; native failure is never promoted to success");
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    Check(sExperimentNativeParams == params, @"B applies to one request only");
    FBTMobileConfigArmEmployeeExperiment(NO);
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params, completion, "", 0);
    Check(sExperimentNativeParams == params && [sLastNativeEvent[@"experiment_profile"] isEqual:@"A_native"], @"A preserves original native request");
    FBTMCRequestPairs existing = params; existing.emplace_back("is_employee", "false");
    FBTMobileConfigArmEmployeeExperiment(YES);
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", existing, completion, "", 0);
    Check(sExperimentNativeParams == existing && [sLastNativeEvent[@"experiment_state"] isEqual:@"skipped_existing_native_field"], @"existing native field never replaced or duplicated");
    NSLog(@"PASS: HTTP error body/status, move ownership, callback forwarding, endpoint filter, logging-off and copy limits");
} return 0; }



