// Tweak.x — FBTweaks bootstrap + exact Facebook tab button long-press.
//
// The working entrypoint is the tab item's inner button/control:
//   FDSTouchStateAnnouncingControl : UIButton, frame ~= (0 0; 44 52)
// and sometimes its direct wrapper UIView with the same frame.
//
// Startup rule: this file installs ONLY the menu entry gesture. No MobileConfig,
// no LiquidGlass, no runtime scan, no prefs warmup, no logs in constructor.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <math.h>
#import "FBGramPrefix.h"
#import "Menu/FBGRSurfaceListVC.h"

static const void *kFBGRExactTabButtonAttached = &kFBGRExactTabButtonAttached;

@interface FBGRExactTabButtonTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)openFromLongPress:(UILongPressGestureRecognizer *)g;
- (void)openFromTripleTap:(UITapGestureRecognizer *)g;
@end

@implementation FBGRExactTabButtonTarget
+ (instancetype)shared {
    static FBGRExactTabButtonTarget *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (void)openFromLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    FBGRPresentMenu();
}

- (void)openFromTripleTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateRecognized) return;
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

    if ([n isEqualToString:@"FDSTouchStateAnnouncingControl"] &&
        FBGRSizeLooksLikeTabButton(v.bounds.size)) return YES;

    if ([n isEqualToString:@"UIView"] &&
        FBGRSizeLooksLikeTabButton(v.bounds.size) &&
        FBGRViewIsInsideFacebookTabButtonTree(v)) return YES;

    if ([n containsString:@"FBTabBarItemDefaultView"]) return YES;

    return NO;
}

static void FBGRDisableNativeLongPressesInSubviewTree(UIView *v, NSUInteger depth) {
    if (!v || depth > 3) return;
    for (UIGestureRecognizer *gr in v.gestureRecognizers.copy) {
        if ([gr isKindOfClass:UILongPressGestureRecognizer.class]) gr.enabled = NO;
    }
    for (UIView *sub in v.subviews) FBGRDisableNativeLongPressesInSubviewTree(sub, depth + 1);
}

static void FBGRAttachExactTabButtonGesture(UIView *v) {
    if (!FBGRIsExactTabButtonCandidate(v)) return;
    if ([objc_getAssociatedObject(v, kFBGRExactTabButtonAttached) boolValue]) return;

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
}

static void FBGRScanExactTabButtons(UIView *root, NSUInteger depth) {
    if (!root || depth > 8) return;
    FBGRAttachExactTabButtonGesture(root);
    for (UIView *sub in root.subviews) FBGRScanExactTabButtons(sub, depth + 1);
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
