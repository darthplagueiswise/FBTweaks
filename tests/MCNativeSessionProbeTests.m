#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTMCNativeSessionProbes.m"
#import "../src/Runtime/FBTNativeTrace.h"

// Real native probe controller + Live Trace linked into a Foundation fixture.
// Native installers/status providers are intentionally deterministic test fakes.
NSString * const FBTKeyMobileConfigFetchDiagnosticsEnabled = @"test.qe_diag";
NSString * const FBTKeyNativeTraceEnabled = @"test.native_trace";
static BOOL sDiagnosticsEnabled = NO;
static BOOL sManualTraceEnabled = NO;
static BOOL sUnknownHookStatus = NO;
static BOOL sAllowNativeInstall = NO;
static BOOL sTigonInstalled = NO;
static BOOL sFetcherInstalled = NO;
static NSUInteger sTigonInstallCalls = 0, sFetcherInstallCalls = 0;
static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
@implementation FBTDefaults
+ (BOOL)boolForKey:(NSString *)key {
    if ([key isEqualToString:FBTKeyNativeTraceEnabled]) return sManualTraceEnabled;
    return [key isEqualToString:FBTKeyMobileConfigFetchDiagnosticsEnabled] && sDiagnosticsEnabled;
}
@end
void FBTMobileConfigResponseCaptureInstallTigon(void) {
    ++sTigonInstallCalls;
    sTigonInstalled = sAllowNativeInstall;
}
void FBTMobileConfigFetcherCaptureInstall(void) {
    ++sFetcherInstallCalls;
    sFetcherInstalled = sAllowNativeInstall;
}
NSDictionary *FBTMobileConfigTigonCaptureStatus(void) {
    if (sUnknownHookStatus) return @{@"simple_callback_failure": [NSNull null]};
    return @{@"simple_callback_hooks_installed": @(sTigonInstalled),
             @"simple_callback_failure": sTigonInstalled ? @"" :
                 sTigonInstallCalls ? @"test_slot_validation_rejected" : @"not_attempted"};
}
NSDictionary *FBTMobileConfigFetcherCaptureStatus(void) {
    if (sUnknownHookStatus) return @{@"native_mc_fetcher_failure": @"unknown"};
    return @{@"native_mc_fetcher_installed": @(sFetcherInstalled),
             @"native_mc_fetcher_failure": sFetcherInstalled ? @"dynamic_RTTI_class_vtable_verified" :
                 sFetcherInstallCalls ? @"test_slot_validation_rejected" : @"not_attempted"};
}
void FBTMobileConfigFetchDiagnosticsRecord(NSString *event, NSDictionary *details) {
    FBTNativeTraceRecordNetwork(event, details);
}
int main(void) { @autoreleasepool {
    Check(!FBTMCNativeProbeAnyEnabled(), @"probes default to OFF");
    Check(!FBTNativeTraceIsEnabled(), @"collector defaults to OFF");
    Check([FBTNativeTraceSnapshot()[@"observation_state"] isEqual:@"capture_off"],
          @"empty OFF collector is not an observation failure");
    Check(!FBTMCNativeProbeIsKey(@"unknown"), @"unknown keys not accepted");
    Check(!FBTMCNativeProbeSetEnabled(@"unknown", YES, NULL), @"unknown probe rejected");
    NSString *reason = nil;
    Check(!FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, &reason),
          @"diagnostics required before installation");
    Check(sTigonInstallCalls == 0, @"disabled logging never installs native hooks");
    sDiagnosticsEnabled = YES;
    sUnknownHookStatus = YES;
    Check([FBTNativeTraceSnapshot()[@"network_source_state"] isEqual:@"unknown"],
          @"missing or unknown resolution cannot be reported as a failed hook");
    sUnknownHookStatus = NO;
    Check(!FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, &reason),
          @"failed slot check rejects probe");
    Check(!FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey), @"failed install stays OFF");
    Check(!FBTNativeTraceIsEnabled(), @"failed native install cannot arm collector");
    Check([FBTNativeTraceSnapshot()[@"network_source_state"] isEqual:@"hook_unavailable"],
          @"installation failure differs from an unarmed source");
    sAllowNativeInstall = YES;
    Check(FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, &reason),
          @"verified Tigon hook can arm");
    Check(FBTMCNativeProbeSetEnabled(FBTMCNativeProbeFetcherKey, YES, &reason),
          @"verified fetch hook can arm");
    Check(FBTMCNativeProbeAnyEnabled(), @"active session status is visible");
    Check(FBTNativeTraceIsEnabled(), @"verified native opt-in arms collector with manual preference OFF");
    NSDictionary *trace = FBTNativeTraceSnapshot();
    Check([trace[@"network_source_state"] isEqual:@"armed"], @"armed requires installed source");
    Check([trace[@"observation_state"] isEqual:@"not_observed"] && [trace[@"events"] count] == 0,
          @"arming never fabricates an observed request");
    FBTMobileConfigFetchDiagnosticsRecord(@"native_mc_request", @{@"request_id": @12, @"http_status": @400,
        @"authorization": @"fixture_private_value_must_not_be_exported"});
    trace = FBTNativeTraceSnapshot();
    Check([trace[@"observation_state"] isEqual:@"observed"] && [trace[@"events"] count] == 1,
          @"real sanitized native event reaches collector");
    Check([trace[@"events"][0][@"name"] isEqual:@"native_mc_request"], @"preserves event identity");
    Check([trace[@"events"][0][@"detail"] containsString:@"request_id=12"], @"preserves safe correlation");
    NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:trace options:0 error:nil]
        encoding:NSUTF8StringEncoding];
    Check(![json containsString:@"fixture_private_value_must_not_be_exported"],
          @"collector never copies fields outside its existing metadata allowlist");
    FBTMCNativeProbeDisableAll();
    Check(!FBTMCNativeProbeAnyEnabled(), @"QE-info OFF disarms all native probes");
    Check(!FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey),
          @"Tigon wrapper must become pass-through");
    Check(!FBTMCNativeProbeIsEnabled(FBTMCNativeProbeFetcherKey),
          @"Fetcher wrapper must become pass-through");
    Check([FBTNativeTraceSnapshot()[@"network_source_state"] isEqual:@"not_armed"],
          @"installed forwarding-only wrappers are not armed");
    FBTNativeTraceSetSessionCaptureEnabled(NO);
    FBTNativeTraceClear();
    Check(!FBTNativeTraceIsEnabled() && [FBTNativeTraceSnapshot()[@"events"] count] == 0,
          @"explicit trace OFF stops session collection");
    sManualTraceEnabled = YES;
    FBTNativeTraceReloadPrefs();
    Check(FBTNativeTraceIsEnabled(), @"manual collector remains independent from hooks");
    Check([FBTNativeTraceSnapshot()[@"network_source_state"] isEqual:@"not_armed"],
          @"manual enabled does not claim hooks armed");
    sManualTraceEnabled = NO;
    FBTNativeTraceReloadPrefs();
    FBTNativeTraceSetSessionCaptureEnabled(YES);
    Check(FBTNativeTraceIsEnabled(), @"explicit Names capture arms buffer without installing extra hooks");
    Check(sTigonInstallCalls == 2 && sFetcherInstallCalls == 1, @"collector-only start never installs hooks");
    sDiagnosticsEnabled = NO;
    FBTNativeTraceReloadPrefs();
    Check(!FBTNativeTraceIsEnabled(), @"QE diagnostic OFF also pauses session collector");
    FBTNativeTraceRecordNetwork(@"native_mc_request", @{@"request_id": @13});
    Check([FBTNativeTraceSnapshot()[@"events"] count] == 0, @"paused collector rejects further events");
    FBTNativeTraceSetSessionCaptureEnabled(NO);
    Check(!FBTMCNativeProbeSetEnabled(FBTMCNativeProbeFetcherKey, YES, &reason),
          @"cannot rearm when diagnostics are OFF");
    Check(sFetcherInstallCalls == 1, @"invalid rearm never attempts install");
    NSLog(@"PASS: native session probe lifecycle and fail-closed install");
} return 0; }
