#import "FBTFeatureCatalog.h"
// Visual groups select complete local map records. The legacy group keeps its
// existing curated BOOL list.
@implementation FBTFeatureCatalog
+ (NSArray<NSDictionary *> *)features {
  return @[
    @{ @"id": @"LiquidGlass", @"title": @"Liquid Glass", @"configurationIDs": @[@120162, @102680, @125862] },
    @{ @"id": @"FloatingTab", @"title": @"Floating Tab Bar", @"configurationIDs": @[@80843] },
    @{ @"id": @"DatingGemstone", @"title": @"Employee / Test User / Dogfood (gates)", @"configs": @[
      @{ @"config": @"70946:fb_ford", @"params": @[
        @{ @"idx": @124, @"name": @"is_messenger_enabled" },
        @{ @"idx": @15, @"name": @"work_user" },
        @{ @"idx": @7, @"name": @"enable_glass_panel" },
        @{ @"idx": @6, @"name": @"enable_more_route" },
        @{ @"idx": @5, @"name": @"can_access_internal_settings" },
        @{ @"idx": @4, @"name": @"is_nhanhn_oc_gk" },
        @{ @"idx": @11, @"name": @"is_employee" },
        @{ @"idx": @161, @"name": @"is_f3_enabled" },
      ] },
      @{ @"config": @"74929:tw_is_employee", @"params": @[
        @{ @"idx": @0, @"name": @"enabled" },
      ] },
      @{ @"config": @"17650:enable_secret_panels_for_test_users", @"params": @[
        @{ @"idx": @1, @"name": @"logged_in_user_is_test_account_with_secret_panel_acces" },
      ] },
      @{ @"config": @"97160:xav_switcher_fb_ios_test_user_check_mc", @"params": @[
        @{ @"idx": @0, @"name": @"is_test_user" },
        @{ @"idx": @1, @"name": @"tag_test_users_enabled" },
      ] },
      @{ @"config": @"114381:whitehat_settings_ios", @"params": @[
        @{ @"idx": @0, @"name": @"enabled" },
        @{ @"idx": @2, @"name": @"ig_enabled" },
      ] },
      @{ @"config": @"84491:mobile_config_internal_settings_features", @"params": @[
        @{ @"idx": @1, @"name": @"is_mc_sync_settings_overrides_enabled" },
      ] },
      @{ @"config": @"86927:ios_creation_meaningful_dogfooding", @"params": @[
        @{ @"idx": @1, @"name": @"enable_story_composer_button" },
        @{ @"idx": @0, @"name": @"enable_feed_composer_button" },
      ] },
    ] },
  ];
}
+ (NSArray<NSDictionary *> *)configurationsForFeatureId:(NSString *)featureId
                                  localConfigurations:(NSArray<NSDictionary *> *)configurations {
    NSArray *configurationIDs = nil;
    for (NSDictionary *feature in [self features]) {
        if ([feature[@"id"] isEqualToString:featureId]) {
            configurationIDs = feature[@"configurationIDs"];
            break;
        }
    }
    if (![configurationIDs isKindOfClass:NSArray.class]) return @[];
    NSSet *selectedIDs = [NSSet setWithArray:configurationIDs];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *configuration in configurations) {
        if (configuration[@"id"] && [selectedIDs containsObject:configuration[@"id"]])
            [matches addObject:configuration];
    }
    return [matches copy];
}
@end
