// Tweak.x — FBTweaks bootstrap.
//
// ── Long press: REPLICA EXATA do Glow ────────────────────────────────────────
// Glow cria ToastWindow : UIWindow com:
//   • windowLevel = UIWindowLevelAlert + 1
//   • canBecomeKeyWindow → NO         (Facebook mantém foco)
//   • shouldAffectStatusBarAppearance → NO
//   • hitTest:withEvent: → nil SEMPRE  (pass-through total ao Facebook)
//   • DVNLongPressGestureRecognizer adicionado À WINDOW (não a uma subview)
//
// UIKit entrega eventos de gesture recognizer independentemente do hitTest.
// Gesture recognizers em UIWindow recebem raw touch events mesmo com hitTest=nil.
// Ao detectar long press, verifica se a posição é na tab bar (bottom ~90pt).
//
// ── MC hooks: instalação atrasada (2s) ───────────────────────────────────────
// Evita crash de recursão infinita durante com.facebook.startup.asyncpreload.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "FBGramPrefix.h"
#import "Menu/FBGRSurfaceListVC.h"

extern void FBGRLiquidGlassEnsureInstalled(void);
extern void FBGRMCGateHooksEnsureInstalled(void);
extern BOOL FBGRDogFoodIsEnabled(void);
extern NSString *FBGRDogFoodDiagnostic(void);

// ── FBGROverlayWindow — replica do ToastWindow do Glow ───────────────────────
@interface FBGROverlayWindow : UIWindow
@end

@implementation FBGROverlayWindow

// Igual ao Glow: canBecomeKeyWindow NO → Facebook não perde foco
- (BOOL)canBecomeKeyWindow { return NO; }

// Igual ao Glow: não afeta status bar
- (BOOL)_shouldAffectStatusBarAppearance { return NO; }
- (BOOL) shouldAffectStatusBarAppearance { return NO; }

// CRÍTICO — igual ao Glow: hitTest SEMPRE nil → pass-through total ao Facebook.
// Gesture recognizers na window continuam recebendo eventos raw de qualquer forma.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

@end

// ── Long press handler ────────────────────────────────────────────────────────
@interface FBGRLPHandler : NSObject
+ (instancetype)shared;
- (void)handleLP:(UILongPressGestureRecognizer *)g;
@end

@implementation FBGRLPHandler
+ (instancetype)shared {
    static FBGRLPHandler *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [self new]; });
    return s;
}
- (void)handleLP:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;

    // Verifica se o toque está na tab bar (bottom ~90pt) — igual ao Glow
    UIView *v = g.view;
    if (!v) return;
    CGPoint pt = [g locationInView:v];
    CGFloat screenH = v.bounds.size.height;

    // Tab bar region: bottom 90pt (covers tab bar + safe area)
    if (pt.y < screenH - 90) return;

    FBGRLogHook("LP", "long-press at %.0f,%.0f (screen=%.0f) → menu", pt.x, pt.y, screenH);
    FBGRPresentMenu();
}
@end

// ── Setup ─────────────────────────────────────────────────────────────────────
static FBGROverlayWindow *gOverlayWindow = nil;

static void FBGRSetupOverlayWindow(void) {
    if (gOverlayWindow) return;

    // Obter a window scene (iOS 13+)
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    UIScreen *screen = UIScreen.mainScreen;
    FBGROverlayWindow *w;
    if (scene) {
        w = [[FBGROverlayWindow alloc] initWithWindowScene:scene];
    } else {
        w = [[FBGROverlayWindow alloc] initWithFrame:screen.bounds];
    }

    w.backgroundColor = [UIColor clearColor];
    w.windowLevel = UIWindowLevelAlert + 1;  // Igual ao Glow: UIWindowLevelAlert
    w.userInteractionEnabled = YES;
    w.rootViewController = [UIViewController new];
    w.rootViewController.view.backgroundColor = [UIColor clearColor];
    [w makeKeyAndVisible];
    [w resignKeyWindow];  // Garante que Facebook mantém o key window

    // Gesture adicionado À WINDOW — igual ao Glow (não a uma subview)
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[FBGRLPHandler shared]
                action:@selector(handleLP:)];
    lp.minimumPressDuration  = 0.5;   // Glow usa curto para ser responsivo
    lp.numberOfTouchesRequired = 1;
    lp.cancelsTouchesInView  = NO;    // Não cancela touches no Facebook
    lp.delaysTouchesBegan    = NO;
    [w addGestureRecognizer:lp];

    gOverlayWindow = w;
    FBGRLogHook("LP", "overlay window created level=%.0f", w.windowLevel);
}

// ── Hook UIApplication para setup no momento certo ───────────────────────────
// Igual ao Glow: application:didFinishLaunchingWithOptions:
%hook UIApplication

- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    BOOL r = %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        FBGRSetupOverlayWindow();
    });
    return r;
}

%end

// ── %ctor ─────────────────────────────────────────────────────────────────────
%ctor {
    @autoreleasepool {
        FBGRLogHook("Main", "FBTweaks loaded into %@",
            NSBundle.mainBundle.bundleIdentifier);
        FBGRLiquidGlassEnsureInstalled();
        FBGRMCGateHooksEnsureInstalled();
        FBGRLogHook("Main", "init done");
    }
}
