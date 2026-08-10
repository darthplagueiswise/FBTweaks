#import "FBTDefaults.h"

NSString * const FBTKeyMasterEnabled         = @"fbt_master_enabled";
NSString * const FBTKeyEmployeeEnabled       = @"fbt_employee_enabled";
NSString * const FBTKeyTestUserEnabled       = @"fbt_test_user_enabled";
NSString * const FBTKeyKnownDogfoodEnabled   = @"fbt_known_dogfood_enabled";
NSString * const FBTKeyReactNativeInternalEnabled = @"fbt_react_native_internal_enabled";
NSString * const FBTKeyBetaBuildEnabled      = @"fbt_beta_build_enabled";
NSString * const FBTKeyEmployeeSweepEnabled  = @"fbt_employee_sweep_enabled";
NSString * const FBTKeyDogfoodSweepEnabled   = @"fbt_dogfood_sweep_enabled";
NSString * const FBTKeyInternalDebugSweepEnabled = @"fbt_internal_debug_sweep_enabled";
NSString * const FBTKeyInternalCImportsEnabled = @"fbt_internal_c_imports_enabled";
NSString * const FBTKeyEasyGatingInternalEnabled = @"fbt_easygating_internal_enabled";
NSString * const FBTKeyLiquidGlassEnabled    = @"fbt_liquidglass_enabled";
NSString * const FBTKeyFloatingTabBarEnabled = @"fbt_floating_tabbar_enabled";
NSString * const FBTKeyDatingEnabled         = @"fbt_dating_enabled";
NSString * const FBTKeyOpenLongPress         = @"fbt_open_longpress_enabled";

NSString * const FBTKeyMessengerInternalSettingsEnabled = @"fbt_messenger_internal_settings_enabled";
NSString * const FBTKeyMessengerInternalToolsEnabled = @"fbt_messenger_internal_tools_enabled";
NSString * const FBTKeyMessengerHomebaseEnabled = @"fbt_messenger_homebase_enabled";
NSString * const FBTKeyMessengerHouseholdEnabled = @"fbt_messenger_household_enabled";

NSString * const FBTKeyMobileConfigRuntimeEnabled   = @"fbt_mobileconfig_runtime_enabled";
NSString * const FBTKeyMobileConfigNativeUIWarmupEnabled = @"fbt_mobileconfig_native_ui_warmup_enabled";
NSString * const FBTKeyMobileConfigCaptureEnabled   = @"fbt_mobileconfig_capture_enabled";
NSString * const FBTKeyMobileConfigOverridesEnabled = @"fbt_mobileconfig_overrides_enabled";
NSString * const FBTKeyMobileConfigOverrides        = @"fbt_mobileconfig_overrides";

NSString * const FBTKeyRuntimeBoolBrowserEnabled = @"fbt_runtime_bool_browser_enabled";
NSString * const FBTKeyRuntimeBoolOverrides      = @"fbt_runtime_bool_overrides";

NSString * const FBTNotificationPrefsChanged = @"FBTNotificationPrefsChanged";

static NSDictionary *gRegistered = nil;

@implementation FBTDefaults

+ (NSDictionary *)defaultsDictionary {
    return @{
        FBTKeyMasterEnabled:                    @(YES),
        FBTKeyEmployeeEnabled:                  @(NO),
        FBTKeyTestUserEnabled:                  @(NO),
        FBTKeyKnownDogfoodEnabled:              @(NO),
        FBTKeyReactNativeInternalEnabled:       @(NO),
        FBTKeyBetaBuildEnabled:                 @(NO),
        FBTKeyEmployeeSweepEnabled:             @(NO),
        FBTKeyDogfoodSweepEnabled:              @(NO),
        FBTKeyInternalDebugSweepEnabled:        @(NO),
        FBTKeyInternalCImportsEnabled:          @(NO),
        FBTKeyEasyGatingInternalEnabled:        @(NO),
        FBTKeyLiquidGlassEnabled:               @(NO),
        FBTKeyFloatingTabBarEnabled:            @(NO),
        FBTKeyDatingEnabled:                    @(NO),
        FBTKeyOpenLongPress:                    @(YES),

        FBTKeyMessengerInternalSettingsEnabled: @(NO),
        FBTKeyMessengerInternalToolsEnabled:    @(NO),
        FBTKeyMessengerHomebaseEnabled:         @(NO),
        FBTKeyMessengerHouseholdEnabled:        @(NO),

        // Runtime browsers ficam ON por padrão. v3.1 mantém MobileConfig em fishhook-only
        // para não tocar __TEXT assinado; varredura pesada é on-demand.
        FBTKeyMobileConfigRuntimeEnabled:       @(NO),
        FBTKeyMobileConfigNativeUIWarmupEnabled:@(YES),
        FBTKeyMobileConfigCaptureEnabled:       @(YES),
        FBTKeyMobileConfigOverridesEnabled:     @(YES),
        FBTKeyMobileConfigOverrides:            @{},

        FBTKeyRuntimeBoolBrowserEnabled:        @(YES),
        FBTKeyRuntimeBoolOverrides:             @{},
    };
}

+ (void)registerDefaultsOnce {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gRegistered = [self defaultsDictionary];
        [[NSUserDefaults standardUserDefaults] registerDefaults:gRegistered];
    });
}

+ (NSDictionary *)registeredDefaults {
    return gRegistered ?: [self defaultsDictionary];
}

+ (BOOL)isMasterExemptKey:(NSString *)key {
    return [key isEqualToString:FBTKeyMasterEnabled] ||
           [key isEqualToString:FBTKeyOpenLongPress];
}

+ (BOOL)boolForKey:(NSString *)key {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![self isMasterExemptKey:key]) {
        if (![ud boolForKey:FBTKeyMasterEnabled]) return NO;
    }
    return [ud boolForKey:key];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [self notifyPrefsChanged];
}

+ (NSString *)stringForKey:(NSString *)key {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [obj isKindOfClass:[NSString class]] ? obj : nil;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    if (value) [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [self notifyPrefsChanged];
}

+ (NSDictionary *)dictForKey:(NSString *)key {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

+ (void)setDict:(NSDictionary *)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setObject:(value ?: @{}) forKey:key];
    [self notifyPrefsChanged];
}

+ (NSArray *)arrayForKey:(NSString *)key {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [obj isKindOfClass:[NSArray class]] ? obj : @[];
}

+ (void)setArray:(NSArray *)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setObject:(value ?: @[]) forKey:key];
    [self notifyPrefsChanged];
}

+ (void)removeObjectForKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [self notifyPrefsChanged];
}

+ (void)notifyPrefsChanged {
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:FBTNotificationPrefsChanged object:nil];
}

@end
