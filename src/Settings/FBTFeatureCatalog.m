#import "FBTFeatureCatalog.h"
// Registro gerado de mc_overrides.json + id_name_mapping.json. Apenas params BOOL.
@implementation FBTFeatureCatalog
+ (NSArray<NSDictionary *> *)features {
  return @[
    @{ @"id": @"LiquidGlass", @"title": @"Liquid Glass", @"configs": @[
      @{ @"config": @"120162:fds_ios_liquid_glass", @"params": @[
        @{ @"idx": @3, @"name": @"context_menu_liquid_animation_enabled" },
        @{ @"idx": @7, @"name": @"floating_tab_bar_glass_effect_enabled" },
        @{ @"idx": @0, @"name": @"context_menu_glass_effect_enabled" },
        @{ @"idx": @6, @"name": @"reactions_menu_glass_effect_enabled" },
      ] },
      @{ @"config": @"102680:mios_liquid_glass", @"params": @[
        @{ @"idx": @41, @"name": @"is_tab_bar_view_based_rendering_enabled" },
        @{ @"idx": @37, @"name": @"reuse_existing_containers_in_set_view_controllers" },
        @{ @"idx": @34, @"name": @"cache_navbar_layout_sizes" },
        @{ @"idx": @28, @"name": @"use_static_navbar_height" },
        @{ @"idx": @21, @"name": @"is_dogfooding_enabled" },
        @{ @"idx": @18, @"name": @"is_view_controller_embedded_toolbar_enabled" },
        @{ @"idx": @17, @"name": @"is_mig_embedded_toolbar_v2_enabled" },
        @{ @"idx": @12, @"name": @"default_to_embedded_bar_implementation" },
        @{ @"idx": @8, @"name": @"me_settings_embedded_navbar" },
        @{ @"idx": @7, @"name": @"is_new_toolbar_enabled" },
        @{ @"idx": @24, @"name": @"enable_inbox_context_menu_custom" },
        @{ @"idx": @20, @"name": @"enable_inbox_context_menu" },
        @{ @"idx": @10, @"name": @"inbox_embedded_navbar" },
        @{ @"idx": @9, @"name": @"more_menu_embedded_navbar" },
        @{ @"idx": @5, @"name": @"enable_embedded_navbar" },
        @{ @"idx": @4, @"name": @"enable_custom_context_menu" },
        @{ @"idx": @6, @"name": @"threadview_embedded_navbar" },
      ] },
      @{ @"config": @"125862:fbios_liquid_glass_sessionless", @"params": @[
        @{ @"idx": @1, @"name": @"is_killswitch_enabled" },
        @{ @"idx": @0, @"name": @"is_enabled" },
      ] },
    ] },
    @{ @"id": @"FloatingTab", @"title": @"Floating Tab Bar", @"configs": @[
      @{ @"config": @"80843:fbios_navigation_floating_tab_bar", @"params": @[
        @{ @"idx": @133, @"name": @"dedicated_floating_tab_bar_pan_uses_chase" },
        @{ @"idx": @132, @"name": @"dedicated_floating_tab_bar_enable_pan_to_switch" },
        @{ @"idx": @131, @"name": @"dedicated_floating_tab_bar_use_accent_selection" },
        @{ @"idx": @130, @"name": @"use_dedicated_floating_tab_bar" },
        @{ @"idx": @129, @"name": @"detach_orphan_nav_items_on_vc_storage" },
        @{ @"idx": @127, @"name": @"enable_darker_pill_background" },
        @{ @"idx": @123, @"name": @"news_feed_force_floating_style" },
        @{ @"idx": @98, @"name": @"enable_thick_material_blur_style" },
        @{ @"idx": @46, @"name": @"enable_scroll_behind_ftb_on_dating" },
        @{ @"idx": @34, @"name": @"enable_tab_bar_tap_highlight_with_image" },
        @{ @"idx": @22, @"name": @"enable_theme_based_gradient_mask" },
        @{ @"idx": @136, @"name": @"enable_xlarge_floating_tab_bar" },
        @{ @"idx": @135, @"name": @"dedicated_floating_tab_bar_size_to_fit" },
        @{ @"idx": @134, @"name": @"dedicated_floating_tab_bar_pan_rubber_band" },
        @{ @"idx": @11, @"name": @"enable_gradient_with_media_light" },
        @{ @"idx": @140, @"name": @"dedicated_floating_tab_bar_always_black" },
        @{ @"idx": @9, @"name": @"enable_tab_bar_scrollaway_infra" },
        @{ @"idx": @8, @"name": @"enable_scroll_away_on_profile" },
        @{ @"idx": @137, @"name": @"dedicated_floating_tab_bar_pan_uses_glass_indicator" },
        @{ @"idx": @2, @"name": @"enable_blurred_background" },
        @{ @"idx": @61, @"name": @"enable_larger_floating_tab_bar" },
        @{ @"idx": @0, @"name": @"enable_floating_tab_bar_infra" },
      ] },
    ] },
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
@end
