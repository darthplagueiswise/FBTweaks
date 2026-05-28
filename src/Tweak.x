// Tweak.x - FBTweaks bootstrap + exact Facebook tab long-press hook.
//
// Binary analysis target:
//   FBSharedFramework: FBTabBarPressGestureRecognizer
//   method type: @32@0:8@16:24 -> -initWithTarget:action:
//
// This is the correct insertion point. Previous attempts attached extra
// recognizers to FBTabBar/UITabBar/UIWindow. Facebook already owns the tab
// long-press pipeline, so view-level gestures lose or open the app's native UI.
// Here we hijack the native tab-bar press recognizer itself and replace its
// target/action with FBTweaks.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "FBGramPrefix.h"
#import "Menu/FBGRSurfaceListVC.h"

extern void FBGRLiquidGlassEnsureInstalled(void);

static const void *kFBGRWindowFallbackAttached = &kFBGRWindowFallbackAttached;

@interface FBGRTabPressTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)openFromPress:(UIGestureRecognizer *)g;
- (void)openFromTap:(UITapGestureRecognizer *)g;
@end

@implementation FBGRTabPressTarget
+ (instancetype)shared {
    static FBGRTabPressTarget *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}
- (void)openFromPress:(UIGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan &&
        g.state != UIGestureRecognizerStateRecognized) return;
    FBGRLogHook("TabPress", "opening menu from %@ state=%ld", NSStringFromClass([g class]), (long)g.state);
    FBGRPresentMenu();
}
- (void)openFromTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateRecognized) return;
    FBGRLogHook("Fallback", "opening menu from 3-finger double tap");
    FBGRPresentMenu();
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
@end

static void FBGRConfigurePressRecognizer(id obj) {
    if (![obj isKindOfClass:UIGestureRecognizer.class]) return;
    UIGestureRecognizer *g = (UIGestureRecognizer *)obj;
    g.cancelsTouchesInView = YES;
    g.delegate = [FBGRTabPressTarget shared];
    if ([g respondsToSelector:@selector(setMinimumPressDuration:)]) {
        ((UILongPressGestureRecognizer *)g).minimumPressDuration = 0.50;
    }
    if ([g respondsToSelector:@selector(setDelaysTouchesBegan:)]) g.delaysTouchesBegan = NO;
    if ([g respondsToSelector:@selector(setDelaysTouchesEnded:)]) g.delaysTouchesEnded = NO;
}

static void FBGRAttachWindowFallback(UIWindow *w) {
    if (!w || [objc_getAssociatedObject(w, kFBGRWindowFallbackAttached) boolValue]) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:[FBGRTabPressTarget shared]
        action:@selector(openFromTap:)];
    tap.numberOfTouchesRequired = 3;
    tap.numberOfTapsRequired = 2;
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesBegan = NO;
    tap.delaysTouchesEnded = NO;
    tap.delegate = [FBGRTabPressTarget shared];
    [w addGestureRecognizer:tap];
    objc_setAssociatedObject(w, kFBGRWindowFallbackAttached, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FBGRLogHook("Fallback", "attached 3-finger double-tap to %@", NSStringFromClass([w class]));
}

%hook FBTabBarPressGestureRecognizer

- (id)initWithTarget:(id)target action:(SEL)action {
    id obj = %orig([FBGRTabPressTarget shared], @selector(openFromPress:));
    FBGRConfigurePressRecognizer(obj);
    FBGRLogHook("TabPress", "hijacked initWithTarget:action: originalTarget=%@ originalAction=%@",
                target ? NSStringFromClass([target class]) : @"nil",
                action ? NSStringFromSelector(action) : @"nil");
    return obj;
}

- (void)addTarget:(id)target action:(SEL)action {
    FBGRLogHook("TabPress", "hijacked addTarget:action: originalTarget=%@ originalAction=%@",
                target ? NSStringFromClass([target class]) : @"nil",
                action ? NSStringFromSelector(action) : @"nil");
    %orig([FBGRTabPressTarget shared], @selector(openFromPress:));
    FBGRConfigurePressRecognizer(self);
}

%end

%hook UIWindow

- (void)didMoveToWindow {
    %orig;
    FBGRAttachWindowFallback((UIWindow *)self);
}

- (void)makeKeyAndVisible {
    %orig;
    FBGRAttachWindowFallback((UIWindow *)self);
}

%end

%ctor {
    @autoreleasepool {
        FBGRLogHook("Main", "FBTweaks loaded into %@", NSBundle.mainBundle.bundleIdentifier);
        FBGRLiquidGlassEnsureInstalled();
        for (UIWindow *w in UIApplication.sharedApplication.windows) FBGRAttachWindowFallback(w);
        FBGRLogHook("Main", "init complete; FBTabBarPressGestureRecognizer hook active");
    }
}
