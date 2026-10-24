#import <Foundation/Foundation.h>
#if __has_include("../src/Settings/FBTSettingsCatalog.h")
#import "../src/Settings/FBTSettingsCatalog.h"
NSString * const FBTMCNativeProbeTigonKey = @"fbt_mc_native_tigon_probe_session";
NSString * const FBTMCNativeProbeFetcherKey = @"fbt_mc_native_fetcher_probe_session";
static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@",message); exit(1); } }
static NSArray *Rows(NSArray *sections) {
    NSMutableArray *rows=[NSMutableArray array]; for(NSDictionary *s in sections) [rows addObjectsFromArray:s[@"rows"]]; return rows;
}
static BOOL Has(NSArray *rows, NSString *key, NSString *value) {
    for(NSDictionary *r in rows) if([r[key] isEqual:value]) return YES; return NO;
}
int main() { @autoreleasepool {
    NSArray *home=Rows([FBTSettingsCatalog sectionsForCategory:nil query:@""]);
    Check(Has(home,@"dest",@"qeoptions"),@"QE switches must have a direct home route");
    Check(Has(home,@"dest",@"namesdiagnostic"),@"QE diagnosis must have a direct home route");
    Check(Has(home,@"dest",@"networkinspector"),@"network inspector must have a direct home route");
    Check([FBTSettingsCatalog categories].count==5,@"five clear areas");
    NSMutableSet *switches=[NSMutableSet set], *destinations=[NSMutableSet set], *actions=[NSMutableSet set];
    for(NSDictionary *s in [FBTSettingsCatalog allSections]) for(NSDictionary *r in s[@"rows"]) {
        if(r[@"key"]) { Check(![switches containsObject:r[@"key"]],@"switch owned by one area"); [switches addObject:r[@"key"]]; }
        if(r[@"dest"]) [destinations addObject:r[@"dest"]];
        if(r[@"action"]) [actions addObject:r[@"action"]];
        Check([r[@"title"] length]>0 && [r[@"icon"] length]>0,@"all rows have a title and symbol");
    }
    for(NSString *key in @[@"fbt_master_enabled",@"fbt_open_three_finger_double_tap_enabled",@"fbt_employee_enabled",@"fbt_test_user_enabled",@"fbt_known_dogfood_enabled",@"fbt_react_native_internal_enabled",@"fbt_beta_build_enabled",@"fbt_dogfood_sweep_enabled",@"fbt_internal_debug_sweep_enabled",@"fbt_internal_c_imports_enabled",@"fbt_easygating_internal_enabled",@"fbt_liquidglass_enabled",@"fbt_floating_tabbar_enabled",@"fbt_dating_enabled",@"fbt_mobileconfig_runtime_enabled",@"fbt_mobileconfig_native_ui_warmup_enabled",@"fbt_mobileconfig_capture_enabled",@"fbt_mobileconfig_fetch_diagnostics_enabled",@"fbt_mobileconfig_overrides_enabled",@"fbt_runtime_bool_browser_enabled",@"fbt_mc_native_tigon_probe_session",@"fbt_mc_native_fetcher_probe_session"])
        Check([switches containsObject:key],[NSString stringWithFormat:@"existing preference preserved: %@",key]);
    for(NSString *dest in @[@"localconfig",@"qeoptions",@"namesdiagnostic",@"networkinspector",@"mobileconfig",@"bool",@"boollive",@"livetrace",@"headline",@"flags",@"queries",@"feat:LiquidGlass",@"feat:FloatingTab",@"feat:DatingGemstone"])
        Check([destinations containsObject:dest],@"existing destination preserved");
    for(NSString *action in @[@"native",@"rn_internal",@"whitehat",@"ensure_mc_file",@"qe_ab",@"clear"])
        Check([actions containsObject:action],@"existing action preserved");
    Check(Has(Rows([FBTSettingsCatalog sectionsForCategory:nil query:@"FORCE NAME"]),@"dest",@"qeoptions"),@"search finds old vocabulary");
    Check(Has(Rows([FBTSettingsCatalog sectionsForCategory:nil query:@"skip_qe"]),@"dest",@"qeoptions"),@"search finds protocol field");
    Check(Has(Rows([FBTSettingsCatalog sectionsForCategory:nil query:@"diagnostico qe"]),@"dest",@"namesdiagnostic"),@"search tolerates accents and all tokens");
    Check(Rows([FBTSettingsCatalog sectionsForCategory:nil query:@"no-such-setting-fixture"]).count==0,@"no results stays empty");
    Check(!Has(Rows([FBTSettingsCatalog sectionsForCategory:@"appearance" query:@"device"]),@"dest",@"namesdiagnostic"),@"category search cannot escape its area");
    Check([FBTSettingsCatalog sectionsForCategory:@"missing-category" query:@""].count==0,@"unknown category fails closed");
    NSLog(@"settings navigation catalog passed");
} return 0; }
#else
int main() { @autoreleasepool { NSLog(@"FAIL: settings catalog missing; QE editor has no direct root route"); } return 1; }
#endif
