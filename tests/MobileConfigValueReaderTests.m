#import <Foundation/Foundation.h>
#include <dlfcn.h>
extern BOOL FBTMobileConfigShouldBypassTweakOverrides(void) __attribute__((weak_import));
#import "../src/Runtime/FBTMobileConfigValueReader.h"
#import "../src/Runtime/FBTLocalConfigCatalog.h"
#import "../src/Runtime/FBTNativeMobileConfigOverrides.h"
#import "../src/Runtime/FBTMobileConfigRuntime.h"

typedef struct mc_bool_param_t { uint64_t value; } mc_bool_param_t;
static NSArray *sContexts;
static BOOL sForced, sThrow;
static id sSystemValue;
static int sUnit = 1;
static NSInteger sBypassSource = 2;
static NSUInteger sChecks, sReloadCalls;
static BOOL sReloadOK = YES;
static id sReloadValue;
BOOL FBTNativeMobileConfigReloadOverridesForContext(id context, NSString **reason) {
    ++sReloadCalls;
    if (!sReloadOK) { if (reason) *reason = @"fixture reload refused"; return NO; }
    sSystemValue = sReloadValue;
    return YES;
}
NSString *NSStringFromFBMobileConfigOptionsValueSource(NSInteger value) {
    return @{@(-1): @"UNKNOWN_SOURCE", @0: @"SERVER", @1: @"OVERRIDE", @2: @"DEFAULT__SERVER_RETURNED_NULL", @9: @"MCS_CLIENT_OVERRIDE"}[@(value)] ?: @"UNKNOWN_SOURCE";
}
NSArray *FBTNativeMobileConfigReaderContexts(void) { return sContexts; }
NSDictionary *FBTMobileConfigOverrideForKey(uint64_t key) {
    return sForced && !(FBTMobileConfigShouldBypassTweakOverrides ? FBTMobileConfigShouldBypassTweakOverrides() : FBTMobileConfigIsInspectingSystemValue()) ? @{@"t": @"bool", @"v": @YES} : nil;
}
@implementation FBTLocalConfigCatalog
+ (NSNumber *)packedKeyForConfiguration:(NSDictionary *)configuration parameter:(NSDictionary *)parameter { return parameter[@"test_key"]; }
@end

@interface FBMobileConfigOptions : NSObject
@property BOOL ignore, noLogging, requestSource;
@property NSInteger valueSource;
- (id)setWithoutLogging;
- (id)setRequestForValueSource;
- (id)setIgnoreOverrideForInternalUse;
@end
@implementation FBMobileConfigOptions
- (id)setWithoutLogging { self.noLogging = YES; return self; }
- (id)setRequestForValueSource { self.requestSource = YES; return self; }
- (id)setIgnoreOverrideForInternalUse { self.ignore = YES; return self; }
@end

static void Check(BOOL value, NSString *message) { ++sChecks; if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
@interface FixtureReader : NSObject
- (int)getUnitType;
- (BOOL)hasValidManager;
- (BOOL)hasValidConfig;
- (BOOL)getBool:(mc_bool_param_t)param withOptions:(FBMobileConfigOptions *)options;
- (int64_t)getInt64:(mc_bool_param_t)param withOptions:(FBMobileConfigOptions *)options;
- (double)getDouble:(mc_bool_param_t)param withOptions:(FBMobileConfigOptions *)options;
- (id)getString:(mc_bool_param_t)param withOptions:(FBMobileConfigOptions *)options;
@end
static void VerifyOptions(FBMobileConfigOptions *options) {
    Check(options.noLogging && options.requestSource, @"inspection requests source without exposure logging");
    Check(options.ignore == FBTMobileConfigIsInspectingSystemValue(), @"native bypass and thread-local bypass agree");
    if (sThrow) @throw [NSException exceptionWithName:@"FixtureRead" reason:@"fixture" userInfo:nil];
    options.valueSource = options.ignore ? sBypassSource : 1;
}
@implementation FixtureReader
- (int)getUnitType { return sUnit; }
- (BOOL)hasValidManager { return YES; }
- (BOOL)hasValidConfig { return YES; }
- (BOOL)getBool:(mc_bool_param_t)param withOptions:(FBMobileConfigOptions *)options {
    VerifyOptions(options);
    return FBTMobileConfigOverrideForKey(param.value) ? YES : [sSystemValue boolValue];
}
- (int64_t)getInt64:(mc_bool_param_t)param withOptions:(FBMobileConfigOptions *)options { VerifyOptions(options); return [sSystemValue longLongValue]; }
- (double)getDouble:(mc_bool_param_t)param withOptions:(FBMobileConfigOptions *)options { VerifyOptions(options); return [sSystemValue doubleValue]; }
- (id)getString:(mc_bool_param_t)param withOptions:(FBMobileConfigOptions *)options { VerifyOptions(options); return sSystemValue; }
@end
static NSDictionary *Read(NSString *type) {
    return FBTMobileConfigInspectParameter(@{}, @{@"id": @0, @"type": type, @"test_key": @((uint64_t)1 << 54)});
}
int main(void) { @autoreleasepool {
    sContexts = @[[FixtureReader new]];
    sForced = YES; sSystemValue = @NO;
    NSDictionary *r = Read(@"bool");
    Check([r[@"available"] boolValue] && ![r[@"system_value"] boolValue] && [r[@"effective_value"] boolValue], @"SYS false and active override true remain separate");
    Check([r[@"effective_source"] isEqual:@"Override da tweak"] && [r[@"source_raw"] integerValue] == 2, @"source recorded without claiming overridden value is server");
    Check([r[@"system_available"] boolValue] && [r[@"source"] hasPrefix:@"DEFAULT"], @"native default stays distinct from a server value");
    Check([r[@"native_effective_value"] isEqual:@NO], @"native override read excludes tweak forcing true");
    Check([r[@"native_effective_source"] isEqual:@"OVERRIDE"], @"native override source is reported separately");
    Check(!FBTMobileConfigIsInspectingSystemValue(), @"inspection scope restored");
    typedef NSDictionary *(*ReloadReadFn)(NSDictionary *, NSDictionary *);
    ReloadReadFn reloadRead = (ReloadReadFn)dlsym(RTLD_DEFAULT, "FBTMobileConfigReloadAndInspectParameter");
    Check(reloadRead != NULL, @"explicit reload and readback API exists");
    NSDictionary *cfg = @{@"id": @103647, @"name": @"mobilehome_startup"};
    NSDictionary *param = @{@"id": @3, @"type": @"bool", @"name": @"mobileconfig_use_intern_graph", @"test_key": @((uint64_t)1 << 54)};
    sReloadValue = @YES;
    r = reloadRead(cfg, param);
    Check(sReloadCalls == 1 && [r[@"reload_returned"] boolValue] && [r[@"native_effective_value"] isEqual:@YES], @"explicit reload happens before native readback");
    Check(![r[@"import_confirmed"] boolValue], @"returning a table never claims parser success");
    sReloadOK = NO; r = reloadRead(cfg, param);
    Check(![r[@"available"] boolValue] && [r[@"reason"] isEqual:@"fixture reload refused"], @"reload failure is unavailable rather than old success");
    sReloadOK = YES;
    sContexts = @[[FixtureReader new], [FixtureReader new]];
    NSUInteger calls = sReloadCalls; r = reloadRead(cfg, param);
    Check(![r[@"available"] boolValue] && sReloadCalls == calls, @"ambiguous scope never reloads either context");
    sContexts = @[[FixtureReader new]];

    sForced = NO; sSystemValue = @YES; r = Read(@"bool");
    Check([r[@"system_value"] boolValue] && [r[@"effective_value"] boolValue], @"SYS true observed independently of an override");
    sSystemValue = @((int64_t)INT64_MAX); r = Read(@"int64");
    Check([r[@"system_value"] longLongValue] == INT64_MAX, @"full int64 precision");
    sSystemValue = @1.25; r = Read(@"double"); Check([r[@"system_value"] doubleValue] == 1.25, @"double ABI");
    sSystemValue = @"a:b\ntext"; r = Read(@"string"); Check([r[@"system_value"] isEqual:sSystemValue], @"string content preserved");
    sSystemValue = nil; r = Read(@"string"); Check(r[@"system_value"] == NSNull.null, @"nil native string preserved");
    sUnit = 4; Check(![Read(@"bool")[@"available"] boolValue], @"wrong universe never reused"); sUnit = 1;
    sContexts = @[[FixtureReader new], [FixtureReader new]]; Check(![Read(@"bool")[@"available"] boolValue], @"ambiguous contexts rejected");
    sContexts = @[]; Check(![Read(@"bool")[@"available"] boolValue], @"missing context is unavailable, not false");
    Check(![FBTMobileConfigInspectParameter(@{}, @{@"type": @"bool"})[@"available"] boolValue], @"unverified descriptor rejected");
    sContexts = @[[FixtureReader new]]; sThrow = YES;
    Check(![Read(@"bool")[@"available"] boolValue] && !FBTMobileConfigIsInspectingSystemValue(), @"exception restores bypass scope");
    sThrow = NO; sSystemValue = @NO;
    Check([Read(@"bool")[@"available"] boolValue], @"reading recovers after an exception");
    sBypassSource = 0; r = Read(@"bool");
    Check([r[@"system_available"] boolValue] && [r[@"source"] isEqual:@"SERVER"], @"server source decoded by native formatter");
    for (NSNumber *source in @[@(-1), @1, @9]) {
        sBypassSource = source.integerValue; r = Read(@"bool");
        Check([r[@"available"] boolValue] && ![r[@"system_available"] boolValue] && r[@"system_value"] == NSNull.null, @"unknown or still-overridden value is not presented as SYS");
    }
    Check([FBTMobileConfigValueText(@NO, @"bool") isEqual:@"false"], @"false displayed explicitly");
    Check([FBTMobileConfigValueText(@YES, @"bool") isEqual:@"true"], @"true displayed explicitly");
    Check([FBTMobileConfigValueText(@"", @"string") isEqual:@"\"\""], @"empty string differs from missing");
    NSLog(@"PASS: %lu native value inspection checks", (unsigned long)sChecks);
} return 0; }
