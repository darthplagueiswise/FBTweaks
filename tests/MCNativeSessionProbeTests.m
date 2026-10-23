#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTMCNativeSessionProbes.m"

// Real native probe controller linked into a small, Foundation-only fixture.
// Native installers/status providers are intentionally deterministic test fakes.
NSString * const FBTKeyMobileConfigFetchDiagnosticsEnabled = @"test.qe_diag";
static BOOL sDiagnosticsEnabled = NO;
static BOOL sAllowNativeInstall = NO;
static BOOL sTigonInstalled = NO;
static BOOL sFetcherInstalled = NO;
static NSUInteger sTigonInstallCalls = 0, sFetcherInstallCalls = 0;
static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
@implementation FBTDefaults
+ (BOOL)boolForKey:(NSString *)key {
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
    return @{@"simple_callback_hooks_installed": @(sTigonInstalled),
             @"simple_callback_failure": @"test_slot_validation_rejected"};
}
NSDictionary *FBTMobileConfigFetcherCaptureStatus(void) {
    return @{@"native_mc_fetcher_installed": @(sFetcherInstalled),
             @"native_mc_fetcher_failure": @"test_slot_validation_rejected"};
}
void FBTMobileConfigFetchDiagnosticsRecord(NSString *event, NSDictionary *details) {
    (void)event; (void)details;
}
int main(void) { @autoreleasepool {
    Check(!FBTMCNativeProbeAnyEnabled(), @"probes default to OFF");
    Check(!FBTMCNativeProbeIsKey(@"unknown"), @"unknown keys not accepted");
    Check(!FBTMCNativeProbeSetEnabled(@"unknown", YES, NULL), @"unknown probe rejected");
    NSString *reason = nil;
    Check(!FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, &reason),
          @"diagnostics required before installation");
    Check(sTigonInstallCalls == 0, @"disabled logging never installs native hooks");
    sDiagnosticsEnabled = YES;
    Check(!FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, &reason),
          @"failed slot check rejects probe");
    Check(!FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey), @"failed install stays OFF");
    sAllowNativeInstall = YES;
    Check(FBTMCNativeProbeSetEnabled(FBTMCNativeProbeTigonKey, YES, &reason),
          @"verified Tigon hook can arm");
    Check(FBTMCNativeProbeSetEnabled(FBTMCNativeProbeFetcherKey, YES, &reason),
          @"verified fetch hook can arm");
    Check(FBTMCNativeProbeAnyEnabled(), @"active session status is visible");
    FBTMCNativeProbeDisableAll();
    Check(!FBTMCNativeProbeAnyEnabled(), @"QE-info OFF disarms all native probes");
    Check(!FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey),
          @"Tigon wrapper must become pass-through");
    Check(!FBTMCNativeProbeIsEnabled(FBTMCNativeProbeFetcherKey),
          @"Fetcher wrapper must become pass-through");
    sDiagnosticsEnabled = NO;
    Check(!FBTMCNativeProbeSetEnabled(FBTMCNativeProbeFetcherKey, YES, &reason),
          @"cannot rearm when diagnostics are OFF");
    Check(sFetcherInstallCalls == 1, @"invalid rearm never attempts install");
    NSLog(@"PASS: native session probe lifecycle and fail-closed install");
} return 0; }
