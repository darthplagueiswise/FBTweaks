#import "FBGRGateRegistry.h"
#import "FBGRMCCatalog.h"

@implementation FBGRFeaturedFlag
+ (instancetype)slotId:(uint64_t)s title:(NSString *)t detail:(NSString *)d { FBGRFeaturedFlag *f=[self new]; f.slotId=s; f.title=t; f.detail=d; return f; }
@end
@implementation FBGRGateProvider
+ (instancetype)id:(NSString *)pid title:(NSString *)t icon:(NSString *)i color:(NSString *)c flags:(NSArray<FBGRFeaturedFlag *> *)flags { FBGRGateProvider *p=[self new]; p.providerID=pid; p.title=t; p.icon=i; p.accentColor=c; p.featured=flags; return p; }
@end
@implementation FBGRGateRegistry

static BOOL FBGRParamMatches(FBGRMCParam *p, NSArray<NSString *> *needles) {
    if (![p.type isEqualToString:@"boolValue"]) return NO;
    NSString *hay = [NSString stringWithFormat:@"%@:%@", p.group ?: @"", p.paramName ?: @""].lowercaseString;
    for (NSString *n in needles) if ([hay containsString:n.lowercaseString]) return YES;
    return NO;
}
static NSArray<FBGRFeaturedFlag *> *FBGRFlagsFor(NSArray<NSString *> *needles, NSUInteger limit) {
    [[FBGRMCCatalog shared] loadIfNeeded];
    NSMutableArray<FBGRFeaturedFlag *> *out=[NSMutableArray array];
    for (FBGRMCParam *p in [[FBGRMCCatalog shared] boolParams]) {
        if (!FBGRParamMatches(p, needles)) continue;
        NSString *d = [NSString stringWithFormat:@"%@ • default=%@ • unit=%ld", p.group ?: @"", p.defaultBool?@"YES":@"NO", (long)p.unitType];
        [out addObject:[FBGRFeaturedFlag slotId:p.slotId title:p.fullKey detail:d]];
        if (out.count >= limit) break;
    }
    return out;
}
static void FBGRAddProvider(NSMutableArray *providers, NSString *pid, NSString *title, NSString *icon, NSString *color, NSArray<NSString *> *needles, NSUInteger limit) {
    NSArray *flags = FBGRFlagsFor(needles, limit);
    if (flags.count) [providers addObject:[FBGRGateProvider id:pid title:title icon:icon color:color flags:flags]];
}
+ (NSArray<FBGRGateProvider *> *)allProviders {
    NSMutableArray *providers=[NSMutableArray array];
    FBGRAddProvider(providers, @"employee_internal", @"Employee / Internal", @"person.badge.key.fill", @"orange", @[@"is_employee", @"employee", @"internal"], 14);
    FBGRAddProvider(providers, @"dogfood_dlp", @"DogFood / DLP", @"ladybug.fill", @"orange", @[@"dogfood", @"dogfooding", @"dlp"], 14);
    FBGRAddProvider(providers, @"floating_tab_bar", @"Floating Tab Bar", @"rectangle.bottomthird.inset.filled", @"blue", @[@"floating_tab_bar", @"tab_bar", @"tabbar", @"scroll_behind"], 12);
    FBGRAddProvider(providers, @"ama_gen_ai", @"AMA / GenAI", @"sparkles", @"purple", @[@"ama_gen_ai", @"gen_ai", @"ai_", @"assistant"], 14);
    FBGRAddProvider(providers, @"marketplace_ai", @"Marketplace / AI", @"cart.fill", @"green", @[@"marketplace", @"mp_ai", @"mp_", @"pdp_ai"], 14);
    FBGRAddProvider(providers, @"navigation_ui", @"Navigation / UI", @"sidebar.squares.leading", @"teal", @[@"navigation", @"navbar", @"tab", @"chrome", @"sidebar"], 14);
    FBGRAddProvider(providers, @"gemstone_dating", @"Gemstone / Dating", @"heart.fill", @"pink", @[@"gemstone", @"dating", @"match", @"crush"], 14);
    FBGRAddProvider(providers, @"debug_tools", @"Debug / Tools", @"wrench.and.screwdriver.fill", @"cyan", @[@"debug", @"tool", @"diagnostic", @"overlay"], 14);
    return providers;
}
@end
