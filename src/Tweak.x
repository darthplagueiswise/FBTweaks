// Tweak.x — FBTweaks bootstrap + long-press on UITabBar to open menu.
//
// Ativação: long-press 2 dedos por 0.65s na tab bar.
// Mesmo padrão do WATweaks (long-press na UITableView de Settings).
// Glow.dylib hookeia setTabBarViewOffsetFraction: na mesma tab bar —
// não interfere porque usamos gesture recognizer, não hook de método.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <substrate.h>
#import "FBGramPrefix.h"
#import "Menu/FBGRSurfaceListVC.h"

extern "C" void FBGRLiquidGlassEnsureInstalled(void);
extern "C" void FBGRMCGateHooksEnsureInstalled(void);

// ── Long press handler ────────────────────────────────────────────────────────
static const void *kFBGRTabBarLP = &kFBGRTabBarLP;

@interface FBGRLPTarget : NSObject
+ (instancetype)shared;
- (void)lp:(UILongPressGestureRecognizer *)g;
@end

@implementation FBGRLPTarget
+ (instancetype)shared {
    static FBGRLPTarget *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [self new]; });
    return s;
}
- (void)lp:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    FBGRLogHook("TabBar", "long-press → menu");
    FBGRPresentMenu();
}
@end

static void FBGRAttachToTabBar(UITabBar *tb) {
    if (!tb || [objc_getAssociatedObject(tb, kFBGRTabBarLP) boolValue]) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[FBGRLPTarget shared] action:@selector(lp:)];
    lp.numberOfTouchesRequired = 2;      // 2-finger: avoids conflito com tap normal
    lp.minimumPressDuration    = 0.65;
    lp.cancelsTouchesInView    = NO;
    [tb addGestureRecognizer:lp];
    objc_setAssociatedObject(tb, kFBGRTabBarLP, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FBGRLogHook("TabBar", "long-press attached to %@", NSStringFromClass([tb class]));
}

// Hook UITabBar didMoveToWindow — fires whenever a tab bar is added to a window.
// Same pattern WATweaks uses on UITableView.
%hook UITabBar

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    FBGRAttachToTabBar(self);
}

%end

// ── %ctor ─────────────────────────────────────────────────────────────────────
%ctor {
    @autoreleasepool {
        FBGRLogHook("Main", "FBTweaks loaded into %@", NSBundle.mainBundle.bundleIdentifier);
        FBGRLiquidGlassEnsureInstalled();
        FBGRMCGateHooksEnsureInstalled();
        FBGRLogHook("Main", "init complete");
    }
}
