// Tweak.x — FBTweaks bootstrap + exact Facebook tab button long-press.
//
// Runtime/FLEX inspection confirmed the working touch target is not UITabBar and
// not the FBTabBarViewController itself. It is the tab item's inner button/control:
//   FDSTouchStateAnnouncingControl : UIButton, frame ~= (0 0; 44 52)
// and sometimes its direct wrapper UIView with the same frame.
//
// This hook attaches our recognizer directly to those controls only, disables
// native UILongPress recognizers in that tiny subtree, and does not install any
// global multi-finger gesture that can steal random touches.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <math.h>
#import "FBGramPrefix.h"
#import "Menu/FBGRSurfaceListVC.h"

extern void FBGRLiquidGlassEnsureInstalled(void);
extern void FBGRGateStoreWarmup(void);
extern void FBGRMCGateHooksApplyPersistedOverrides(void);
extern void FBGRDogFoodApplyPersistentState(void);

static const void *kFBGRExactTabButtonAttached = &kFBGRExactTabButtonAttached;

@interface FBGRExactTabButtonTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)openFromLongPress:(UILongPressGestureRecognizer *)g;
- (void)openFromTripleTap:(UITapGestureRecognizer *)g;
@end

@implementation FBGRExactTabButtonTarget
+ (instancetype)shared {
    static FBGRExactTabButtonTarget *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}
- (void)openFromLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    FBGRLogHook("Menu", "open from exact tab button longpress: %@", NSStringFromClass([g.view class]));
    FBGRPresentMenu();
}
- (void)openFromTripleTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateRecognized) return;
    FBGRLogHook("Menu", "open from exact tab button triple tap: %@", NSStringFromClass([g.view class]));
    FBGRPresentMenu();
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}
@end

static BOOL FBGRSizeLooksLikeTabButton(CGSize s) {
    CGFloat w = fabs(s.width), h = fabs(s.height);
    return (w >= 38.0 && w <= 56.0 && h >= 44.0 && h <= 60.0);
}

static BOOL FBGRViewIsInsideFacebookTabButtonTree(UIView *v) {
    if (!v) return NO;
    for (UIView *p = v; p; p = p.superview) {
        NSString *n = NSStringFromClass([p class]);
        if ([n containsString:@"FBTabBarItemDefaultView"]) return YES;
        if ([n containsString:@"FBTabBar"]) return YES;
        if ([n containsString:@"TabBarItem"]) return YES;
    }
    return NO;
}

static BOOL FBGRIsExactTabButtonCandidate(UIView *v) {
    if (!v || !v.window) return NO;
    NSString *n = NSStringFromClass([v class]);

    // Exact class from the user's FLEX screenshot and Facebook binary:
    // FDSTouchStateAnnouncingControl : UIButton, frame (0 0; 44 52)
    if ([n isEqualToString:@"FDSTouchStateAnnouncingControl"] &&
        FBGRSizeLooksLikeTabButton(v.bounds.size)) return YES;

    // Wrapper UIView from the screenshot: <UIView frame=(0 0; 44 52)>
    if ([n isEqualToString:@"UIView"] &&
        FBGRSizeLooksLikeTabButton(v.bounds.size) &&
        FBGRViewIsInsideFacebookTabButtonTree(v)) return YES;

    // Also attach to FBTabBarItemDefaultView itself as a parent fallback.
    if ([n containsString:@"FBTabBarItemDefaultView"]) return YES;

    return NO;
}

static void FBGRDisableNativeLongPressesInSubviewTree(UIView *v, NSUInteger depth) {
    if (!v || depth > 3) return;
    for (UIGestureRecognizer *gr in v.gestureRecognizers.copy) {
        if ([gr isKindOfClass:UILongPressGestureRecognizer.class]) {
            gr.enabled = NO;
        }
    }
    for (UIView *sub in v.subviews) FBGRDisableNativeLongPressesInSubviewTree(sub, depth + 1);
}

static void FBGRAttachExactTabButtonGesture(UIView *v) {
    if (!FBGRIsExactTabButtonCandidate(v)) return;
    if ([objc_getAssociatedObject(v, kFBGRExactTabButtonAttached) boolValue]) return;

    // Disable only native longpress recognizers in this tiny tab-button subtree.
    // Normal tap still works because UIControl touch-up/tap recognizers are left intact.
    FBGRDisableNativeLongPressesInSubviewTree(v, 0);

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[FBGRExactTabButtonTarget shared]
        action:@selector(openFromLongPress:)];
    lp.minimumPressDuration = 0.42;
    lp.numberOfTouchesRequired = 1;
    lp.cancelsTouchesInView = YES;
    lp.delaysTouchesBegan = NO;
    lp.delaysTouchesEnded = YES;
    lp.delegate = [FBGRExactTabButtonTarget shared];
    [v addGestureRecognizer:lp];

    // Non-global fallback restricted to this same button: triple-tap with one finger.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:[FBGRExactTabButtonTarget shared]
        action:@selector(openFromTripleTap:)];
    tap.numberOfTouchesRequired = 1;
    tap.numberOfTapsRequired = 3;
    tap.cancelsTouchesInView = YES;
    tap.delaysTouchesBegan = NO;
    tap.delaysTouchesEnded = YES;
    tap.delegate = [FBGRExactTabButtonTarget shared];
    [v addGestureRecognizer:tap];

    v.userInteractionEnabled = YES;
    objc_setAssociatedObject(v, kFBGRExactTabButtonAttached, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FBGRLogHook("TabButton", "attached exact button gesture to %@ frame=%@", NSStringFromClass([v class]), NSStringFromCGRect(v.frame));
}

static void FBGRScanExactTabButtons(UIView *root, NSUInteger depth) {
    if (!root || depth > 8) return;
    FBGRAttachExactTabButtonGesture(root);
    for (UIView *sub in root.subviews) FBGRScanExactTabButtons(sub, depth + 1);
}

static void FBGRScanAllWindowsForExactTabButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)scene).windows) FBGRScanExactTabButtons(w, 0);
            }
        } else {
            for (UIWindow *w in UIApplication.sharedApplication.windows) FBGRScanExactTabButtons(w, 0);
        }
    });
}

%hook FDSTouchStateAnnouncingControl

- (void)didMoveToWindow {
    %orig;
    FBGRAttachExactTabButtonGesture((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    FBGRAttachExactTabButtonGesture((UIView *)self);
}

%end

%hook FBTabBarItemDefaultView

- (void)didMoveToWindow {
    %orig;
    FBGRScanExactTabButtons((UIView *)self, 0);
}

- (void)layoutSubviews {
    %orig;
    FBGRScanExactTabButtons((UIView *)self, 0);
}

%end

%hook UIWindow

- (void)didAddSubview:(UIView *)subview {
    %orig;
    FBGRScanExactTabButtons(subview, 0);
}

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *n = NSStringFromClass([self class]);
    if ([n containsString:@"TabBar"] || [n containsString:@"Root"] || [n containsString:@"Home"]) {
        FBGRScanExactTabButtons(self.view, 0);
    }
}

%end

%ctor {
    @autoreleasepool {
        FBGRLogHook("Main", "FBTweaks loaded into %@", NSBundle.mainBundle.bundleIdentifier);
        FBGRLiquidGlassEnsureInstalled();
        FBGRGateStoreWarmup();
        FBGRMCGateHooksApplyPersistedOverrides();
        FBGRDogFoodApplyPersistentState();
        FBGRScanAllWindowsForExactTabButton();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ FBGRScanAllWindowsForExactTabButton(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ FBGRScanAllWindowsForExactTabButton(); });
        FBGRLogHook("Main", "init complete");
    }
}
