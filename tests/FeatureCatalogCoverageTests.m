#import <Foundation/Foundation.h>
#import "../src/Settings/FBTFeatureCatalog.h"

// macOS: clang -fobjc-arc -framework Foundation tests/FeatureCatalogCoverageTests.m \
//   src/Settings/FBTFeatureCatalog.m -o /tmp/fbt-feature-catalog-tests
static void Check(BOOL result, NSString *message) {
    if (!result) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) { @autoreleasepool {
    NSDictionary *fourTypes = @{@"id": @120162, @"name": @"fixture_glass", @"ordinal": @3,
        @"source": @"params_map_kMobileConfigAdminId.txt", @"scope": @"Page / Admin ID",
        @"params": @[
            @{@"id": @0, @"name": @"fixture_bool", @"type": @"bool", @"slot": @0},
            @{@"id": @1, @"name": @"fixture_integer", @"type": @"int64", @"slot": @4},
            @{@"id": @2, @"name": @"fixture_text", @"type": @"string", @"slot": @2},
            @{@"id": @177, @"name": @"fixture_fraction", @"type": @"double", @"slot": @6}
        ]};
    NSDictionary *rnGlass = @{@"id": @120162, @"name": @"fixture_glass", @"ordinal": @7,
        @"source": @"rn_params_map_u4.txt", @"scope": @"rn_params_map_u4.txt",
        @"params": @[@{@"id": @88, @"name": @"fixture_rn_only", @"type": @"bool", @"slot": @19}]};
    NSDictionary *unknown = @{@"id": @102680, @"ordinal": @8,
        @"source": @"params_map_kMobileConfigAdminId.txt", @"scope": @"Page / Admin ID",
        @"params": @[@{@"id": @99, @"slot": @3}, @{@"id": @100, @"type": @"unrecognized"}]};
    NSDictionary *sessionless = @{@"id": @125862, @"name": @"", @"ordinal": @9,
        @"source": @"params_map.txt", @"scope": @"App / Sessionless", @"params": @[]};
    NSDictionary *floatingAdmin = @{@"id": @80843, @"name": @"fixture_floating", @"ordinal": @11,
        @"source": @"params_map_kMobileConfigAdminId.txt", @"scope": @"Page / Admin ID",
        @"params": @[@{@"id": @187, @"name": @"fixture_style", @"type": @"int64", @"slot": @6}]};
    NSDictionary *floatingRN = @{@"id": @80843, @"name": @"fixture_floating", @"ordinal": @1,
        @"source": @"rn_params_map_u4.txt", @"scope": @"rn_params_map_u4.txt",
        @"params": @[@{@"id": @130, @"name": @"fixture_rn_floating", @"type": @"bool", @"slot": @8}]};
    NSDictionary *unrelated = @{@"id": @999999, @"name": @"fixture_unrelated", @"params": @[]};
    NSDictionary *legacy = @{@"id": @70946, @"name": @"fixture_legacy", @"params": @[]};
    NSArray *catalog = @[unrelated, fourTypes, floatingAdmin, rnGlass, unknown, sessionless, floatingRN, legacy];
    NSData *before = [NSJSONSerialization dataWithJSONObject:catalog options:NSJSONWritingSortedKeys error:nil];

    NSArray *glass = [FBTFeatureCatalog configurationsForFeatureId:@"LiquidGlass" localConfigurations:catalog];
    Check(glass.count == 4, @"all matching configuration records survive the visual feature selection");
    Check([glass[0] isEqual:fourTypes] && [glass[1] isEqual:rnGlass], @"admin and RN records for one ID retain their separate scope and parameters");
    NSArray *parameters = glass[0][@"params"];
    Check(parameters.count == 4, @"visual selection keeps every parameter instead of only curated BOOL indices");
    Check([[NSSet setWithArray:[parameters valueForKey:@"type"]] isEqual:[NSSet setWithArray:@[@"bool", @"int64", @"string", @"double"]]], @"all four types reach the typed editor unchanged");
    Check([glass[2] isEqual:unknown] && glass[2][@"name"] == nil, @"a missing configuration name is not invented");
    Check(glass[2][@"params"][0][@"name"] == nil && glass[2][@"params"][0][@"type"] == nil &&
        [glass[2][@"params"][1][@"type"] isEqual:@"unrecognized"], @"unknown parameter names and types are preserved without guesses");
    Check([glass[3] isEqual:sessionless], @"sessionless scope and an empty explicit name remain intact");

    NSArray *floating = [FBTFeatureCatalog configurationsForFeatureId:@"FloatingTab" localConfigurations:catalog];
    Check(floating.count == 2 && [floating[0] isEqual:floatingAdmin] && [floating[1] isEqual:floatingRN], @"Floating Tab keeps both admin and RN records");
    Check([FBTFeatureCatalog configurationsForFeatureId:@"DatingGemstone" localConfigurations:catalog].count == 0, @"the legacy group is not expanded from local metadata");
    Check([FBTFeatureCatalog configurationsForFeatureId:@"fixture_unknown" localConfigurations:catalog].count == 0, @"an unknown feature does not expose unrelated configurations");
    Check([FBTFeatureCatalog configurationsForFeatureId:@"LiquidGlass" localConfigurations:@[]].count == 0, @"an absent local configuration never falls back to stale curated indices");
    Check([[NSJSONSerialization dataWithJSONObject:catalog options:NSJSONWritingSortedKeys error:nil] isEqual:before], @"selection leaves the supplied catalog unchanged");
    NSLog(@"PASS: visual feature coverage, typed parameters, scopes and unknown metadata");
} return 0; }
