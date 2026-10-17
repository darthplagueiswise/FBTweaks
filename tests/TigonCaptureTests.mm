#import <Foundation/Foundation.h>
#include <cstring>
#import "../src/Runtime/FBTMobileConfigTigonCapture.mm"
#import "../src/Runtime/FBTMobileConfigFetcherCapture.mm"

NSString * const FBTKeyMobileConfigFetchDiagnosticsEnabled = @"test.capture";
static BOOL sEnabled = YES;
@implementation FBTDefaults
+ (BOOL)boolForKey:(NSString *)key { return sEnabled; }
@end

static NSMutableArray *sSaved, *sEvents;
static NSDictionary *sLastNativeEvent;
static NSUInteger sBodyCalls, sResponseCalls, sEndCalls;
static void *sExpectedBodyArgument, *sExpectedResponse, *sExpectedSummary;
static void Check(BOOL result, NSString *message) { if (!result) { NSLog(@"FAIL: %@", message); exit(1); } }
void FBTMobileConfigFetchDiagnosticsRecord(NSString *event, NSDictionary *details) { [sEvents addObject:event]; if ([event isEqual:@"native_mc_fetch_completed"]) sLastNativeEvent = [details copy]; }
void FBTMobileConfigResponseCaptureRecordTransportEvent(NSString *event, NSDictionary *details) { [sEvents addObject:event]; }
NSDictionary *FBTMobileConfigResponseCaptureArmInfo(void) { return @{}; }
BOOL FBTMobileConfigResponseCaptureShouldCaptureRequest(NSString *, NSString *, NSString *) { return YES; }
void FBTMobileConfigResponseCaptureWriteRawBody(NSData *data, NSString *, NSString *, NSString *, NSDictionary *state,
        NSString *, NSInteger status, NSString *, NSString *) {
    if (!sEnabled) return;
    [sSaved addObject:@{@"data": [data copy], @"status": @(status), @"provenance": state[@"payload_provenance"] ?: @""}];
}
BOOL FBTRebindVerifiedMainConstSlot(uint64_t, const unsigned char *, const char *, void *, void **, NSString **) { return NO; }
BOOL FBTRebindVerifiedImageConstSlot(const char *, uint64_t, const unsigned char *, uint64_t, void *, void **, NSString **) { return NO; }
int rebind_symbols(struct rebinding[], size_t) { return 0; }

struct TestRequest { std::string host, path, method, query; };
static const void *URL(const void *r) { return r; }
static const std::string &Host(const void *r) { return ((const TestRequest *)r)->host; }
static const std::string &Path(const void *r) { return ((const TestRequest *)r)->path; }
static const std::string &Method(const void *r) { return ((const TestRequest *)r)->method; }
static const std::string &Query(const void *r) { return ((const TestRequest *)r)->query; }
static void ResponseOriginal(void *, void *r) {
    Check(r == sExpectedResponse, @"response forwarded unchanged"); ++sResponseCalls;
}
static void BodyOriginal(void *, void *b) {
    Check(b == sExpectedBodyArgument && *(void **)b != nullptr, @"body ownership preserved until original");
    *(void **)b = nullptr; ++sBodyCalls;
}
static void EndOriginal(void *, void *summary) {
    Check(summary == sExpectedSummary, @"summary forwarded unchanged");
    Check(sSaved.count == 1, @"HTTP error body saved before native conversion"); ++sEndCalls;
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
static void CompletionFromNativeEOM(void *, void *summary) {
    Check(summary == sExpectedSummary, @"EOM summary preserved without onStarted");
    sDeferredCompletion(false, sNativeBody);
}
int main(void) { @autoreleasepool {
    sSaved = [NSMutableArray array]; sEvents = [NSMutableArray array];
    sTigonCaptureLock = [NSLock new]; sTigonCapturedRequests = [NSMutableDictionary dictionary];
    sTigonRequestURL = URL; sTigonURLHost = Host; sTigonURLPath = Path; sTigonURLQuery = Query; sTigonRequestMethod = Method;
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
    Check([FBTMobileConfigTigonCaptureObserveNativeCompletion(@{}, NO)[@"native_tigon_correlation"] isEqual:@"no_simple_eom_scope"],
        @"unrelated completion cannot reuse a previous native response");
    sEnabled = NO;
    Check(FBTMobileConfigTigonCaptureObserveNativeCompletion(@{}, NO).count == 0, @"logging off disables native correlation");
    NSLog(@"PASS: HTTP error body/status, move ownership, callback forwarding, endpoint filter, logging-off and copy limits");
} return 0; }
