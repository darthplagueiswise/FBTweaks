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

        // ── LiquidGlass ──────────────────────────────────────────────────────
        // _METAIsLiquidGlassEnabled is a C function hooked via fishhook.
        // The MC params below affect specific LG sub-behaviors.
        [FBGRGateProvider id:@"liquidglass" title:@"LiquidGlass" icon:@"drop.fill" color:@"cyan"
            flags:@[
                F(0,    @"_METAIsLiquidGlassEnabled", @"C gate (fishhook) — ativa todo o pipeline LG"),
                F(3402, @"liquid_glass_bottom_inset_only", @"oculus_twilight_notif — bottom inset LG"),
                F(3422, @"liquid_glass_simple_avatar_icon", @"oculus_twilight_router — avatar icon LG"),
            ]],

        // ── Floating TabBar ──────────────────────────────────────────────────
        [FBGRGateProvider id:@"floatingtabbar" title:@"Floating Tab Bar" icon:@"rectangle.bottomthird.inset.filled" color:@"blue"
            flags:@[
                F(1214, @"bottom_inset_marketplace_feed", @"default TRUE — já ativo"),
                F(1215, @"floating_cta_local_hub",        @"CTA flutuante no Local Hub"),
                F(1216, @"floating_cta_mp_jobs",          @"CTA flutuante em Marketplace Jobs"),
                F(1217, @"scroll_behind_ftb_dating",      @"★ conteúdo scrolla atrás da tab bar"),
                F(1218, @"safe_area_fixes_mp_rating",     @"fix safe area no MP Rating"),
                F(1219, @"scroll_inset_adj_rn",           @"ajuste de inset RN"),
            ]],

        // ── Navigation / UI ──────────────────────────────────────────────────
        [FBGRGateProvider id:@"navigation" title:@"Navigation / UI" icon:@"sidebar.squares.leading" color:@"purple"
            flags:@[
                F(1488, @"white_chrome_enabled",           @"ios_navigation_white_chrome — chrome branco"),
                F(1495, @"enable_side_bar",                @"ios_ssmc_fbnavigation — sidebar"),
                F(3912, @"should_show_new_sub_nav_bar",    @"rn_gemstone_labs_2025_h2 — nova sub-nav"),
                F(3421, @"enable_tabbed_navigation_improvements", @"oculus_twilight_router"),
                F(3948, @"should_show_explore_tab",        @"rn_gemstone_labs_2026_h1 — tab Explorar"),
                F(3923, @"enable_dh_plinks_to_tabs",       @"rn_gemstone_labs_2026_h1 — plinks p/ tabs"),
            ]],

        // ── Employee / Dogfood ───────────────────────────────────────────────
        [FBGRGateProvider id:@"employee" title:@"Employee / Dogfood" icon:@"person.badge.key.fill" color:@"orange"
            flags:@[
                F(874,  @"fb_ford:is_employee",         @"gate principal de employee (unitType=2)"),
                F(2028, @"messenger_xplat:is_employee", @"gate employee Messenger"),
                F(4620, @"xplat_lwi:is_employee",       @"cross-platform lightweight"),
                F(4120, @"tw_is_employee:enabled",      @"Twilight/Quest employee"),
                F(1247, @"gaming_profile:is_internal",  @"Gaming internal"),
                F(816,  @"enable_employee_debug_tool",  @"fb_daily_games_mc debug tool"),
                F(1263, @"enable_game_tab_dogfooding_tools", @"gaming_tab_rn"),
                F(3103, @"is_internal_user_indicator",  @"oculus_mobile_core"),
            ]],

        // ── Gemstone / Dating ────────────────────────────────────────────────
        [FBGRGateProvider id:@"gemstone" title:@"Gemstone / Dating" icon:@"heart.fill" color:@"pink"
            flags:@[
                F(3948, @"should_show_explore_tab",          @"2026h1 — tab Explorar"),
                F(3930, @"enable_interested_tab_grid_view",  @"2026h1 — grid view"),
                F(3921, @"enable_crush_profile_controls",    @"2026h1"),
                F(3924, @"enable_expiring_likes",            @"2026h1"),
                F(3936, @"enable_smart_filters",             @"2026h1"),
                F(3937, @"enable_sticky_filters",            @"2026h1"),
                F(3934, @"enable_photo_grid",                @"2026h1"),
                F(3952, @"should_show_match_moment",         @"2026h1"),
                F(3912, @"should_show_new_sub_nav_bar",      @"2025h2"),
                F(3900, @"enable_friending_tab_removal",     @"2025h2"),
                F(3897, @"enable_crush_profile_in_queue",    @"2025h2"),
            ]],

        // ── Marketplace / AI ─────────────────────────────────────────────────
        [FBGRGateProvider id:@"marketplace" title:@"Marketplace / AI" icon:@"cart.fill" color:@"green"
            flags:@[
                F(2141, @"enable_feed_floating_icon",   @"mp_ai_assistant_bot — ícone flutuante no feed"),
                F(2145, @"enable_pdp_floating_icon",    @"mp_ai_assistant_bot — PDP"),
                F(2148, @"enable_search_entrypoint",    @"mp_ai_assistant_bot — busca"),
                F(2155, @"show_marketplace_ai_assistant_in_pdp", @"mp_ai_assistant_bot"),
                F(2692, @"enable_pdp_ai_deal_summary",  @"mp_pdp_h1_2026 — resumo AI de deal"),
                F(2831, @"show_non_us_filter_bar_redesign", @"mp_serp_h2_2025"),
                F(1865, @"show_debug_info",             @"marketplace_masonry_feed debug"),
                F(2444, @"enable_csr_debug_overlay",    @"mp_home_perf debug overlay"),
            ]],

        // ── Gaming ───────────────────────────────────────────────────────────
        [FBGRGateProvider id:@"gaming" title:@"Gaming / Daily Games" icon:@"gamecontroller.fill" color:@"teal"
            flags:@[
                F(1247, @"gaming_profile:is_internal",   @"internal access"),
                F(1263, @"enable_game_tab_dogfooding",   @"dogfood tools"),
                F(1271, @"enable_mhe_dogfooding_pill",   @"MHE pill"),
                F(1287, @"show_floating_cta_horizon_video", @"floating CTA"),
                F(816,  @"enable_employee_debug_tool",   @"debug tool"),
                F(827,  @"enable_theme_override",        @"tema override"),
            ]],
    ];
    });
    return providers;
}

@end
