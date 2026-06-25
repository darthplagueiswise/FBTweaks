#import "FBTDefaults.h"

NSString * const FBTKeyMasterEnabled         = @"fbt_master_enabled";
NSString * const FBTKeyEmployeeEnabled       = @"fbt_employee_enabled";
NSString * const FBTKeyLiquidGlassEnabled    = @"fbt_liquidglass_enabled";
NSString * const FBTKeyFloatingTabBarEnabled = @"fbt_floating_tabbar_enabled";
NSString * const FBTKeyDatingEnabled         = @"fbt_dating_enabled";
NSString * const FBTKeyOpenLongPress         = @"fbt_open_longpress_enabled";

NSString * const FBTKeyMobileConfigRuntimeEnabled   = @"fbt_mobileconfig_runtime_enabled";
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
        FBTKeyLiquidGlassEnabled:               @(NO),
        FBTKeyFloatingTabBarEnabled:            @(NO),
        FBTKeyDatingEnabled:                    @(NO),
        FBTKeyOpenLongPress:                    @(YES),

        // Runtime browsers ficam ON por padrão para permitir captura/hook real
        // sem depender de recompilar. O custo no launch é só ler dicionários
        // pequenos e instalar hooks persistidos; varredura pesada é on-demand.
        FBTKeyMobileConfigRuntimeEnabled:       @(YES),
        FBTKeyMobileConfigCaptureEnabled:       @(YES),
        FBTKeyMobileConfigOverridesEnabled:     @(YES),
        FBTKeyMobileConfigOverrides:            @{},

        FBTKeyRuntimeBoolBrowserEnabled:        @(YES),
        FBTKeyRuntimeBoolOverrides:             @{},
        @"fbt_symbol_overrides":                @{},
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
