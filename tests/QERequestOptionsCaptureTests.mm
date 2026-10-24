// Production mode, real fetcher wrapper, only external/native send is doubled.
#define FBT_ENABLE_QE_INVASIVE_HOOKS 0
#define main FBTUnusedTigonFixtureMain
#include "TigonCaptureTests.mm"
#undef main
#import "../src/Runtime/FBTQERequestOptions.h"

static FBTMCRequestPairs sSentOptions;
static const FBTMCRequestPairs *sRetainedOptions;
static unsigned sOptionSends;
static void OptionsNative(const void *, const std::string &method, const std::string &purpose,
        const FBTMCRequestPairs &params, FBTMCCompletion completion, const std::string &hint, uint64_t target) {
    Check(method == "POST" && purpose == "mobileconfig_qe_info" && hint == "fixture_hint" && target == 7,
        @"routing/method/target reach native send unchanged");
    ++sOptionSends; sSentOptions = params; sRetainedOptions = &params;
    sDeferredCompletion = std::move(completion);
}
int main() { @autoreleasepool {
    sEvents = [NSMutableArray array]; sSaved = [NSMutableArray array];
    Check(![FBTQERequestOptionsSnapshot()[@"enabled"] boolValue], @"session starts disabled");
    Check(!FBTQERequestOptionsSetValue(@"access_token", YES), @"unknown/identity fields cannot be edited");
    FBTQERequestOptionsReset(YES);
    FBTQERequestOptionsSetEnabled(YES);
    FBTQERequestOptionsSetAllQE(YES);
    Check(FBTQERequestOptionsSetValue(@"with_params", NO), @"individual false selection accepted");
    sEnabled = YES; sFetcherProbeEnabled = YES; sOriginalFetch = OptionsNative;
    FBTMCRequestPairs native;
    for (const auto key : fbt_qe_options::keys()) native.push_back({key,"false"});
    native.push_back({"device_id","device-fixture"}); native.push_back({"queries","[]"});
    native.push_back({"api_version","9"}); native.push_back({"access_token","private-fixture"});
    const auto original = native;
    int completed = 0;
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", native,
        [&](bool ok, const std::string &body) {
            Check(!ok && body == "native failure fixture", @"original false and bytes reach caller unchanged"); ++completed;
        }, "fixture_hint", 7);
    Check(sOptionSends == 1 && completed == 0, @"native send once, completion remains asynchronous");
    Check(native == original, @"caller-owned parameter vector is unchanged");
    Check(sSentOptions[0].second == "true" && sSentOptions[4].second == "false" &&
        sSentOptions[8].second == "true" && sSentOptions[9].second == "false", @"custom switches reach real wrapper output");
    Check(sSentOptions[10] == original[10] && sSentOptions[11] == original[11] &&
        sSentOptions[12] == original[12] && sSentOptions[13] == original[13], @"device/queries/version/credential preserved");
    FBTQERequestOptionsSetEnabled(NO); native.clear();
    Check(*sRetainedOptions == sSentOptions, @"outgoing copy stays alive until native completion");
    sDeferredCompletion(false, "native failure fixture"); sDeferredCompletion = nullptr;
    Check(completed == 1, @"completion delivered once");
    Check([sLastNativeEvent[@"qe_request_options_state"] isEqual:@"applied"], @"historical event preserves applied profile");
    Check([sLastNativeEvent[@"device_id_state"] isEqual:@"present_not_validated"] &&
        [sLastNativeEvent[@"device_id_bytes"] integerValue] == 14, @"identity evidence is metadata, not a validity claim");
    FBTQERequestOptionsSetEnabled(YES);
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", original,
        [&](bool ok, const std::string &body) { Check(ok && body == "native success fixture", @"true forwarded unchanged"); }, "fixture_hint", 7);
    sDeferredCompletion(true, "native success fixture"); sDeferredCompletion = nullptr;
    FBTQERequestOptionsSetEnabled(NO);
    FBTMCAsyncFetch(nullptr, "POST", "mobileconfig_qe_info", original,
        [&](bool, const std::string &) {}, "fixture_hint", 7);
    Check(sSentOptions == original, @"disabled profile forwards native request");
    sDeferredCompletion(false, "native failure fixture"); sDeferredCompletion = nullptr;
    Check([sLastNativeEvent[@"qe_request_options_state"] isEqual:@"outside_selected_scope"], @"native baseline labelled");
    FBTQERequestOptionsReset(NO);
    Check(![FBTQERequestOptionsSnapshot()[@"values"][@"with_params"] boolValue] &&
        [FBTQERequestOptionsSnapshot()[@"values"][@"skip_qe"] boolValue], @"native preset restores defaults");
    NSLog(@"QE options native integration passed");
} return 0; }
