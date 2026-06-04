#import "FBGRGateRegistry.h"

@implementation FBGRFeaturedFlag
+ (instancetype)slotId:(uint64_t)s title:(NSString *)t detail:(NSString *)d {
    FBGRFeaturedFlag *f = [self new];
    f.slotId = s; f.title = t; f.detail = d;
    return f;
}
@end

@implementation FBGRGateProvider
+ (instancetype)id:(NSString *)pid title:(NSString *)t icon:(NSString *)i
             color:(NSString *)c flags:(NSArray<FBGRFeaturedFlag *> *)flags {
    FBGRGateProvider *p = [self new];
    p.providerID = pid; p.title = t; p.icon = i; p.accentColor = c; p.featured = flags;
    return p;
}
@end

@implementation FBGRGateRegistry

+ (NSArray<FBGRGateProvider *> *)allProviders {
    static NSArray *providers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{

    // ── Helper macro-like inline ─────────────────────────────────────────────
    FBGRFeaturedFlag *(^F)(uint64_t, NSString *, NSString *) =
        ^(uint64_t s, NSString *t, NSString *d) {
            return [FBGRFeaturedFlag slotId:s title:t detail:d];
        };

    providers = @[

        [FBGRGateProvider id:@"liquidglass" title:@"LiquidGlass / SDK26" icon:@"drop.fill" color:@"cyan"
            flags:@[
                F(0,    @"METAIsLiquidGlassEnabled / slot 0", @"C gate fallback + ObjC IGLiquidGlassExperimentHelper hooks"),
                F(3402, @"oculus_twilight_notif:liquid_glass_bottom_inset_only", @"LiquidGlass related MC"),
                F(3422, @"oculus_twilight_router:liquid_glass_simple_avatar_icon", @"LiquidGlass related MC"),
            ]],

        [FBGRGateProvider id:@"fbios_navigation_floating_tab_bar" title:@"Floating Tab Bar" icon:@"rectangle.bottomthird.inset.filled" color:@"blue"
            flags:@[
                F(1214, @"enable_bottom_inset_on_marketplace_feed", @"default TRUE"),
                F(1215, @"enable_floating_cta_on_local_hub", @"CTA local hub"),
                F(1216, @"enable_floating_cta_on_mp_jobs", @"CTA Marketplace Jobs"),
                F(1217, @"enable_scroll_behind_ftb_on_dating", @"scroll atrás da tab bar"),
                F(1218, @"floating_tab_bar_safe_area_fixes_on_mp_rating", @"safe-area fixes"),
                F(1219, @"scroll_view_content_inset_adjustment_rn", @"RN content inset"),
            ]],

        [FBGRGateProvider id:@"employee" title:@"Employee / Internal" icon:@"person.badge.key.fill" color:@"orange"
            flags:@[
                F(876,  @"fb_ford:is_employee", @"employee principal"),
                F(2028, @"messenger_xplat:is_employee", @"Messenger employee"),
                F(4623, @"xplat_lwi:is_employee", @"xplat lightweight employee"),
                F(4124, @"tw_is_employee:enabled", @"Twilight employee"),
                F(1248, @"gaming_profile:is_internal", @"Gaming internal"),
                F(818,  @"fb_daily_games_mc:enable_employee_debug_tool", @"Daily games debug tool"),
                F(1708, @"marketplace_debug:show_debug_view_in_home_feed_nav_bar", @"Marketplace debug view"),
            ]],

        [FBGRGateProvider id:@"dogfood" title:@"DogFood / DLP" icon:@"ladybug.fill" color:@"orange"
            flags:@[
                F(162,  @"ama_guidance_dogfooding:mock_data_enabled", @"AMA dogfood mock data"),
                F(192,  @"ama_introduce_budget_outcome_forecaster_mc:dogfood_no_slider", @"dogfood no slider"),
                F(292,  @"ama_mfr_adopt_sms_verification_for_lead_quality:dogfooding_enabled", @"lead quality dogfooding"),
                F(551,  @"bizapp_insights:is_tofu_dogfooder", @"Biz tofu dogfooder"),
                F(1264, @"gaming_tab_rn:enable_game_tab_dogfooding_tools", @"Gaming dogfood tools"),
            ]],

        [FBGRGateProvider id:@"ama_gen_ai" title:@"AMA / GenAI" icon:@"sparkles" color:@"purple"
            flags:@[
                F(156, @"ama_gen_ai:enabled", @"GenAI master"),
                F(152, @"ama_gen_ai:creative_fatigue_mfr_enabled", @"creative fatigue MFR"),
                F(154, @"ama_gen_ai:creative_limited_mfr_enabled", @"creative limited MFR"),
                F(158, @"ama_gen_ai:gen_ai_text_overlays_enabled", @"text overlays; default TRUE"),
                F(65,  @"ama_background_generation_mfr:enabled", @"background generation"),
                F(170, @"ama_help_and_support:ai_diagnosis_advertisers", @"AI diagnosis advertisers"),
            ]],

        [FBGRGateProvider id:@"mp_ai_assistant_bot" title:@"Marketplace / AI Assistant" icon:@"cart.fill.badge.plus" color:@"green"
            flags:@[
                F(2142, @"enable_feed_floating_icon", @"feed floating icon"),
                F(2146, @"enable_pdp_floating_icon", @"PDP floating icon"),
                F(2148, @"enable_search_entrypoint", @"search entrypoint"),
                F(2151, @"enable_valet_pdp_chip", @"valet PDP chip"),
                F(2156, @"show_marketplace_ai_assistant_in_pdp", @"assistant in PDP"),
                F(2446, @"mp_home_perf_2024:enable_csr_debug_overlay", @"CSR debug overlay"),
            ]],

        [FBGRGateProvider id:@"rn_gemstone_labs_2026_h1" title:@"Gemstone / Dating 2026" icon:@"heart.fill" color:@"pink"
            flags:@[
                F(3925, @"enable_crush_profile_controls", @"profile controls"),
                F(3927, @"enable_dh_plinks_to_tabs", @"plinks to tabs"),
                F(3928, @"enable_expiring_likes", @"expiring likes"),
                F(3930, @"enable_genai_bio_shortened_disclosure", @"GenAI bio disclosure"),
                F(3935, @"enable_interested_tab_grid_view", @"interested grid view"),
                F(3939, @"enable_photo_grid", @"photo grid"),
                F(3941, @"enable_smart_filters", @"smart filters"),
                F(3942, @"enable_sticky_filters", @"sticky filters"),
                F(3953, @"should_show_explore_tab", @"Explore tab"),
                F(3957, @"should_show_match_moment", @"match moment"),
            ]],

        [FBGRGateProvider id:@"ios_ssmc_fbnavigation" title:@"Navigation / UI" icon:@"sidebar.squares.leading" color:@"teal"
            flags:@[
                F(1496, @"ios_ssmc_fbnavigation_admin_id:enable_side_bar", @"sidebar"),
                F(3916, @"rn_gemstone_labs_2025_h2:should_show_new_sub_nav_bar", @"new sub nav bar"),
                F(3904, @"rn_gemstone_labs_2025_h2:enable_friending_tab_removal", @"friending tab removal"),
                F(3923, @"rn_gemstone_labs_2025_h2:unship_sl_and_stl_from_settings", @"settings cleanup"),
            ]],
    ];
    });
    return providers;
}

@end
