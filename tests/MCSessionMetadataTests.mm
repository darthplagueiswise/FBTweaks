// Reuse transport doubles, but exercise the production session-only branch.
#define FBT_ENABLE_QE_INVASIVE_HOOKS 0
#define main FBTLegacyCaptureFixtureMain
#include "TigonCaptureTests.mm"
#undef main

int main(void) { @autoreleasepool {
    sEvents = [NSMutableArray array]; sSaved = [NSMutableArray array];
    sTigonCaptureLock = [NSLock new]; sTigonCapturedRequests = [NSMutableDictionary dictionary];
    int object = 0;
    NSData *body = [@"{\"error\":{\"code\":100,\"type\":\"OAuthException\",\"message\":\"(#100) Employee Account or Specific App Conditions\"}}" dataUsingEncoding:NSUTF8StringEncoding];
    sTigonCapturedRequests[[NSValue valueWithPointer:&object]] = [@{
        @"mc_correlated": @YES, @"request_id": @88, @"body": [body mutableCopy], @"http_status": @400
    } mutableCopy];
    sOrigTigonEOM = EndOriginal;
    int summary = 0; sExpectedSummary = &summary;
    FBTTigonOnEOM(&object, &summary);
    Check(sEndCalls == 1, @"production observer forwards original callback once with original pointer");
    Check(sSaved.count == 0, @"session-only observer never writes response body files");
    Check([sEvents containsObject:@"names_transport_diagnostic"], @"production metadata reaches existing diagnosis reducer");
    Check([sLastTransportEvent[@"http_status"] isEqual:@400], @"HTTP failure preserved");
    Check([sLastNamesDiagnostic[@"server_error_code"] isEqual:@100] &&
        [sLastNamesDiagnostic[@"server_error_message"] isEqual:@"Employee Account or Specific App Conditions"], @"production probe exposes structured eligibility metadata");
    Check(sTigonCapturedRequests.count == 0, @"terminal capture releases in-memory body");
    sTigonCapturedRequests[[NSValue valueWithPointer:&object]] = [@{
        @"mc_correlated": @NO, @"body": [body mutableCopy]
    } mutableCopy];
    NSUInteger count = sEvents.count;
    FBTTigonFinishCapture(&object);
    Check(sEvents.count == count && sSaved.count == 0, @"unrelated transport body never promoted to QE evidence");
    count = sEvents.count;
    FBTMobileConfigFetcherObserveUIContext([NSObject new], @"session");
    Check(sEvents.count == count, @"unarmed context probe cannot inspect or emit a context association");
    sOriginalFetch = NativeOriginal;
    sNativeBody = "None domain: FBHTTPErrorDomain code: 400 detail: ";
    FBTMCRequestPairs params = {{"needs_name", "true"}, {"skip_qe", "true"}};
    int completions = 0;
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", params,
        [&](bool success, const std::string &value) {
            Check(!success && value == sNativeBody, @"unarmed native fetch preserves original false and error bytes"); ++completions;
        }, "", 0);
    Check(completions == 1 && sNativeCalls == 1 && sEvents.count == count, @"unarmed fetch forwards exactly once without diagnostic events");
    NSLog(@"session-only metadata tests passed");
} return 0; }
