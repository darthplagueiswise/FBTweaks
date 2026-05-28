// Tweak.x — FBTweaks bootstrap + safe menu gestures.
//
// Facebook does not use UIKit's UITabBar for the main navigation. The live
// hierarchy shows FBTabBarViewController plus custom FBTabBar/FBTabBarItemDefaultView
// views. Therefore the menu gesture must attach to Facebook's custom tabbar views,
// not only to UITabBar.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>
#import "FBGramPrefix.h"
#import "Menu/FBGRSurfaceListVC.h"

extern void FBGRLiquidGlassEnsureInstalled(void);

static const void *kFBGRMenuGestureAttached = &kFBGRMenuGestureAttached;
static const void *kFBGRWindowGestureAttached = &kFBGRWindowGestureAttached;

@interface FBGRMenuGestureTarget : NSObject
+ (instancetype)shared;
- (void)openFromLongPress:(UILongPressGestureRecognizer *)g;
- (void)openFromTap:(UITapGestureRecognizer *)g;
@end

@implementation FBGRMenuGestureTarget
+ (instancetype)shared {
    static FBGRMenuGestureTarget *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}
- (void)openFromLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    FBGRLogHook("MenuGesture", "open from long press on %@", NSStringFromClass([g.view class]));
    FBGRPresentMenu();
}
- (void)openFromTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateRecognized) return;
    FBGRLogHook("MenuGesture", "open from fallback tap on %@", NSStringFromClass([g.view class]));
    FBGRPresentMenu();
}
@end

static BOOL FBGRClassNameLooksLikeFacebookTabBar(const char *name) {
    if (!name) return NO;
    // Confirmed by FLEX / binary strings:
    // FBTabBarViewController, FBTabBarItemDefaultView, FBTabBar, FBTabBarContainerView,
    // FBTabBarAndContentView, FBTabBarFloatableContainerView, plus private UIKit platter views.
    return strstr(name, "FBTabBar") != NULL ||
           strstr(name, "_UITabBar") != NULL ||
           strstr(name, "TabBarItemDefaultView") != NULL ||
           strstr(name, "TabBarSelection") != NULL;
}

static void FBGRAttachMenuLongPressToView(UIView *view) {
    if (!view || [objc_getAssociatedObject(view, kFBGRMenuGestureAttached) boolValue]) return;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[FBGRMenuGestureTarget shared]
        action:@selector(openFromLongPress:)];

    // One finger works on FBTabBarItemDefaultView; Facebook's tab bar is not a UIKit UITabBar.
    // We keep cancelsTouchesInView=NO so native tab handling still receives touches.
    lp.numberOfTouchesRequired = 1;
    lp.minimumPressDuration = 0.85;
    lp.cancelsTouchesInView = NO;
    lp.delaysTouchesBegan = NO;
    lp.delaysTouchesEnded = NO;

    [view addGestureRecognizer:lp];
    view.userInteractionEnabled = YES;
    objc_setAssociatedObject(view, kFBGRMenuGestureAttached, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FBGRLogHook("MenuGesture", "attached long press to %@", NSStringFromClass([view class]));
}

static void FBGRAttachFallbackGesturesToWindow(UIWindow *window) {
    if (!window || [objc_getAssociatedObject(window, kFBGRWindowGestureAttached) boolValue]) return;

    // Reliable emergency fallback: double-tap with two fingers anywhere.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:[FBGRMenuGestureTarget shared]
        action:@selector(openFromTap:)];
    tap.numberOfTouchesRequired = 2;
    tap.numberOfTapsRequired = 2;
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesBegan = NO;
    tap.delaysTouchesEnded = NO;
    [window addGestureRecognizer:tap];

    // Secondary fallback: two-finger long press anywhere.
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[FBGRMenuGestureTarget shared]
        action:@selector(openFromLongPress:)];
    lp.numberOfTouchesRequired = 2;
    lp.minimumPressDuration = 0.75;
    lp.cancelsTouchesInView = NO;
    lp.delaysTouchesBegan = NO;
    lp.delaysTouchesEnded = NO;
    [window addGestureRecognizer:lp];

    objc_setAssociatedObject(window, kFBGRWindowGestureAttached, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FBGRLogHook("MenuGesture", "attached fallback gestures to UIWindow");
}

static void FBGRScanTabBarSubviews(UIView *root, NSUInteger depth) {
    if (!root || depth > 5) return;
    const char *name = object_getClassName(root);
    if (FBGRClassNameLooksLikeFacebookTabBar(name)) {
        FBGRAttachMenuLongPressToView(root);
    }
    for (UIView *sub in root.subviews) {
        FBGRScanTabBarSubviews(sub, depth + 1);
    }
}

%hook UIWindow

- (void)didMoveToWindow {
    %orig;
    FBGRAttachFallbackGesturesToWindow((UIWindow *)self);
}

- (void)makeKeyAndVisible {
    %orig;
    FBGRAttachFallbackGesturesToWindow((UIWindow *)self);
}

%end

%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    const char *name = object_getClassName(self);
    if (FBGRClassNameLooksLikeFacebookTabBar(name)) {
        FBGRAttachMenuLongPressToView(self);
    }
}

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    const char *name = object_getClassName(self);
    if (name && strstr(name, "FBTabBarViewController") != NULL) {
        FBGRLogHook("MenuGesture", "FBTabBarViewController appeared; scanning tabbar views");
        FBGRScanTabBarSubviews(self.view, 0);
    }
}

%end

%ctor {
    @autoreleasepool {
        FBGRLogHook("Main", "FBTweaks loaded into %@", NSBundle.mainBundle.bundleIdentifier);
        FBGRLiquidGlassEnsureInstalled();
        FBGRLogHook("Main", "init complete");
    }
}
