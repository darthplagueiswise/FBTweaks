// Tweak.x — FBTweaks bootstrap + long-press na FBTabBar.
//
// IMPORTANTE: este arquivo é compilado como ObjC (.x → .m), NÃO como C++.
// Por isso: usar `extern`, não `extern "C"`.
// Para %hook em classes sem header (FBTabBar, FBTabBarViewController):
//   self.window → cast para UIView* primeiro
//   [self valueForKey:] → cast para (id)self

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "FBGramPrefix.h"
#import "Menu/FBGRSurfaceListVC.h"

// extern (não extern "C") — arquivo .x compila como ObjC, não C++
extern void FBGRLiquidGlassEnsureInstalled(void);
extern void FBGRMCGateHooksEnsureInstalled(void);

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

// ── Attach helper — idempotente ───────────────────────────────────────────────
static void FBGRAttachLP(UIView *view) {
    if (!view || [objc_getAssociatedObject(view, kFBGRGestureKey) boolValue]) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[FBGRLPTarget shared]
                action:@selector(handleLP:)];
    lp.minimumPressDuration    = 0.8;
    lp.numberOfTouchesRequired = 1;
    lp.cancelsTouchesInView    = NO;
    lp.delaysTouchesBegan      = NO;
    [view addGestureRecognizer:lp];
    objc_setAssociatedObject(view, kFBGRGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FBGRLogHook("LP", "attached to %@", NSStringFromClass([view class]));
}

// ── Hook 1: FBTabBar didMoveToWindow ─────────────────────────────────────────
// Logos gera @class FBTabBar (forward), então self é opaco.
// Cast para UIView* antes de acessar qualquer propriedade herdada.
%hook FBTabBar

- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;     // FBTabBar herda de UIView
    if (view.window) FBGRAttachLP(view);
}

%end

// ── Hook 2: FBTabBarViewController viewDidAppear: ────────────────────────────
// self é forward-declared. Cast para (id) antes de mandar mensagem.
// tabBar é propriedade readonly que retorna FBTabBar* (T@"FBTabBar",R,N,V_tabBar).
%hook FBTabBarViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        UIView *tb = (UIView *)[(id)self valueForKey:@"tabBar"];
        if (tb) FBGRAttachLP(tb);
    } @catch (...) {}
}

%end

// ── Hook 3: UITabBarController — fallback para UIKit padrão ──────────────────
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
        FBGRLogHook("Main", "ready — long-press 0.8s na tab bar");
    }
}
