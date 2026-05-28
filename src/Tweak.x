// Tweak.x — FBTweaks bootstrap + long-press on FBTabBar para abrir menu.
//
// DIAGNÓSTICO: o hook anterior usava %hook UITabBar mas o Facebook
// usa FBTabBar (classe própria em FBSharedFramework.framework).
// Confirmado via: strings FBSharedFramework | grep "_OBJC_CLASS_\$_FBTabBar"
// e T@"FBTabBar",R,N,V_tabBar no mesmo framework.
//
// Ativação: long-press 1 dedo, 0.8s, na FBTabBar.
// cancelsTouchesInView=NO → tap normal nos itens continua funcionando.
//
// Estratégia dupla:
//   1. %hook FBTabBar didMoveToWindow  — hook direto na classe correta
//   2. %hook FBTabBarViewController viewDidAppear: — backup via KVC tabBar

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "FBGramPrefix.h"
#import "Menu/FBGRSurfaceListVC.h"

extern "C" void FBGRLiquidGlassEnsureInstalled(void);
extern "C" void FBGRMCGateHooksEnsureInstalled(void);

// ── Gesture target ────────────────────────────────────────────────────────────
static const void *kFBGRGestureKey = &kFBGRGestureKey;

@interface FBGRLPTarget : NSObject
+ (instancetype)shared;
- (void)handleLP:(UILongPressGestureRecognizer *)g;
@end

@implementation FBGRLPTarget
+ (instancetype)shared {
    static FBGRLPTarget *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [self new]; });
    return s;
}
- (void)handleLP:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    FBGRLogHook("LP", "triggered on %@", NSStringFromClass([g.view class]));
    FBGRPresentMenu();
}
@end

// ── Attach helper — idempotente via associated object ─────────────────────────
static void FBGRAttachLP(UIView *view) {
    if (!view || [objc_getAssociatedObject(view, kFBGRGestureKey) boolValue]) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[FBGRLPTarget shared]
                action:@selector(handleLP:)];
    lp.minimumPressDuration  = 0.8;
    lp.numberOfTouchesRequired = 1;   // 1 dedo — igual ao Glow
    lp.cancelsTouchesInView  = NO;    // tap normal continua funcionando
    lp.delaysTouchesBegan    = NO;
    [view addGestureRecognizer:lp];
    objc_setAssociatedObject(view, kFBGRGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FBGRLogHook("LP", "attached to %@ (%@)",
        NSStringFromClass([view class]),
        view.window ? @"has window" : @"no window yet");
}

// ── Hook 1: FBTabBar didMoveToWindow — CLASSE CORRETA ────────────────────────
// FBTabBar está em FBSharedFramework.framework.
// Logos resolve via objc_getClass("FBTabBar") em runtime, sem header.
%hook FBTabBar

- (void)didMoveToWindow {
    %orig;
    if (self.window) FBGRAttachLP((UIView *)self);
}

%end

// ── Hook 2: FBTabBarViewController viewDidAppear: — backup ───────────────────
// FBTabBarViewController tem propriedade tabBar: (T@"FBTabBar",R,N,V_tabBar).
// Usamos valueForKey: para evitar declarar o header completo.
%hook FBTabBarViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        UIView *tb = [self valueForKey:@"tabBar"];
        if (tb) FBGRAttachLP(tb);
    } @catch (...) {}
}

%end

// ── Hook 3: UITabBarController — para o caso de existir também ───────────────
%hook UITabBarController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (self.tabBar) FBGRAttachLP(self.tabBar);
}

%end

// ── %ctor ─────────────────────────────────────────────────────────────────────
%ctor {
    @autoreleasepool {
        FBGRLogHook("Main", "FBTweaks loaded into %@",
            NSBundle.mainBundle.bundleIdentifier);
        FBGRLiquidGlassEnsureInstalled();
        FBGRMCGateHooksEnsureInstalled();
        FBGRLogHook("Main", "hooks ready — activate: long-press 0.8s on tab bar");
    }
}
