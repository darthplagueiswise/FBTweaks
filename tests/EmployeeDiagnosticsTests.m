#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTEmployeeDiagnostics.m"
NSString * const FBTKeyMobileConfigFetchDiagnosticsEnabled = @"test.enabled";
static BOOL enabled = YES, inspecting = NO, synthetic = NO, nativeProbe = NO;
BOOL FBTMCNativeProbeAnyEnabled(void) { return nativeProbe; }
@implementation FBTDefaults
+ (BOOL)boolForKey:(NSString *)key { return enabled; }
@end
@implementation FBTFlagCatalog
+ (NSDictionary *)bestMatchForMobileConfigKey:(uint64_t)key {
    if (key == 1) return @{@"c": @"tw_is_employee", @"p": @"enabled"};
    if (key == 2) return @{@"c": @"tw_video_feed", @"p": @"enabled"};
    if (key == 4) return @{@"c": @"fb_ford", @"p": @"is_employee"};
    if (key == 5) return @{@"c": @"misc", @"p": @"is_test_account"};
    return @{@"c": @"unrelated", @"p": @"enabled"};
}
@end
BOOL FBTMobileConfigIsInspectingSystemValue(void) { return inspecting; }
BOOL FBTMobileConfigShouldBypassTweakOverrides(void) { return inspecting; }
BOOL FBTMobileConfigIsInspectingValue(void) { return inspecting || synthetic; }
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL %@", message); exit(1); } }
int main(void) { @autoreleasepool {
    FBTEmployeeDiagnosticsReset();
    Check([FBTEmployeeDiagnosticsSnapshot()[@"state"] isEqual:@"not_observed"], @"unknown not false");
    FBTEmployeeObserveBool(@"FBUserPreferences.isEmployee", NO, YES, NULL);
    NSDictionary *first = FBTEmployeeDiagnosticsSnapshot()[@"reads"][0];
    Check(![first[@"original_return"] boolValue] && [first[@"effective_return"] boolValue] &&
        [first[@"changed_by_this_tweak"] boolValue], @"original and effective distinguished");
    FBTEmployeeObserveBool(@"FBUserPreferences.isEmployee", YES, YES, NULL);
    Check([FBTEmployeeDiagnosticsSnapshot()[@"reads"][0][@"count"] intValue] == 2, @"counters accumulate");
    Check(!FBTEmployeeApplyTWProbe(1, NO), @"no default force");
    FBTEmployeeArmTWProbe();
    Check(FBTEmployeeApplyTWProbe(1, NO) && !FBTEmployeeApplyTWProbe(2, NO) &&
        !FBTEmployeeApplyTWProbe(3, NO), @"only exact tw_is_employee.enabled affected");
    inspecting = YES;
    Check(!FBTEmployeeApplyTWProbe(1, NO), @"SYS inspection unaffected");
    inspecting = NO; synthetic = YES;
    Check(FBTEmployeeApplyTWProbe(1, NO), @"effective inspection retains temporary tweak forcing");
    FBTEmployeeObserveBool(@"synthetic_direct", NO, YES, NULL);
    FBTEmployeeObserveMCBool(1, NO, YES, NULL);
    Check([FBTEmployeeDiagnosticsSnapshot()[@"reads"] count] == 1, @"synthetic effective reads are not employee observations");
    synthetic = NO; enabled = NO;
    Check(!FBTEmployeeApplyTWProbe(1, NO), @"paused logging disables probe");
    FBTEmployeeObserveBool(@"should_not_exist", NO, YES, NULL);
    Check([FBTEmployeeDiagnosticsSnapshot()[@"reads"] count] == 1, @"paused capture stores nothing");
    nativeProbe = YES;
    FBTEmployeeObserveBool(@"probe_only", NO, NO, NULL);
    Check([FBTEmployeeDiagnosticsSnapshot()[@"reads"] count] == 2,
        @"passive identity capture works when native session probe is armed");
    nativeProbe = NO;
    enabled = YES;
    FBTEmployeeCancelTWProbe();
    Check(!FBTEmployeeApplyTWProbe(1, NO), @"cancellation restores original");
    FBTEmployeeArmTWProbe(); sTWDeadline = [NSProcessInfo processInfo].systemUptime - 1;
    Check(!FBTEmployeeApplyTWProbe(1, NO), @"expired experiment restores original");
    FBTEmployeeDiagnosticsReset();
    FBTEmployeeObserveMCBool(2, NO, NO, NULL);
    FBTEmployeeObserveMCBool(3, NO, YES, NULL);
    FBTEmployeeObserveMCBool(4, NO, NO, NULL);
    FBTEmployeeObserveMCBool(5, NO, NO, NULL);
    Check([FBTEmployeeDiagnosticsSnapshot()[@"reads"] count] == 3, @"tw and employee/test gates observed; unrelated excluded");
    for (int i=0;i<100;i++) FBTEmployeeObserveBool([NSString stringWithFormat:@"fixture%d", i], NO, NO, NULL);
    Check([FBTEmployeeDiagnosticsSnapshot()[@"reads"] count] == 64, @"bounded storage");
    NSLog(@"PASS employee observation and temporary tw experiment");
} return 0; }
