#import "FBTEntryPoints.h"
#import "../FBTPrefix.h"
#import "../FBTDefaults.h"
#import "../FBTUtils.h"
#include "../../modules/fishhook/fishhook.h"
#include <string.h>

// Facebook 583: FBSettingsMenuItemHandler's controller factory returns nil.
// handleMenuItem calls FBSettingsControllerOpenBloksAction (five ObjC objects).
// Scope that native action and mark the controller passed to FBNavigationInfo.
// No title matching, replacement of native screens, or executable-page patch.
typedef void (*FBTSettingsOpenFn)(id, id, id, id, id);
typedef id (*FBTNavigationInfoFn)(id, SEL, UIViewController *, NSUInteger,
                                NSUInteger, id, id);
typedef void (*FBTControllerAppearanceFn)(id, SEL, BOOL);
static FBTSettingsOpenFn sOriginalSettingsOpen;
static FBTNavigationInfoFn sOriginalNavigationInfo;
static FBTControllerAppearanceFn sOriginalViewDidAppear;
static __thread NSUInteger sSettingsNavigationDepth;
static BOOL sSettingsBindingRegistered;
static char kFBTSettingsRootKey, kFBTSettingsButtonKey, kFBTWindowGestureKey;

@interface FBTEntryPointTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)openSettings:(id)sender;
- (void)handleThreeFingerDoubleTap:(UITapGestureRecognizer *)recognizer;
@end

@implementation FBTEntryPointTarget
+ (instancetype)shared {
    static FBTEntryPointTarget *target;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ target = [FBTEntryPointTarget new]; });
    return target;
}
- (void)openSettings:(id)sender {
    UIView *source = [sender isKindOfClass:[UIView class]] ? sender : nil;
    [FBTUtils presentSettingsFromView:source session:[FBTUtils storedSession]];
}
- (void)handleThreeFingerDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateRecognized ||
        ![FBTDefaults boolForKey:FBTKeyOpenThreeFingerDoubleTap]) return;
    [self openSettings:recognizer.view];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

static void FBTAddSettingsIcon(UIViewController *controller) {
    if (!controller || !objc_getAssociatedObject(controller, &kFBTSettingsRootKey)) return;
    UINavigationItem *item = controller.navigationItem;
    UIBarButtonItem *button = objc_getAssociatedObject(controller, &kFBTSettingsButtonKey);
    if (!button) {
        button = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]
                                                 style:UIBarButtonItemStylePlain
                                                target:[FBTEntryPointTarget shared]
                                                action:@selector(openSettings:)];
        button.title = @"FBTweak";
        button.accessibilityLabel = @"FBTweak";
        button.accessibilityHint = @"Abre os ajustes da tweak";
        button.accessibilityIdentifier = @"fbtweak.settings.open";
        objc_setAssociatedObject(controller, &kFBTSettingsButtonKey, button,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([item.rightBarButtonItems containsObject:button]) return;
    NSMutableArray *buttons = [item.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    [buttons addObject:button];
    item.rightBarButtonItems = buttons;
}

static void FBTSettingsOpen(id source, id entryPoint, id session, id coordinator, id intentHandler) {
    if (!sOriginalSettingsOpen) return;
    [FBTUtils setStoredSession:session];
    ++sSettingsNavigationDepth;
    @try { sOriginalSettingsOpen(source, entryPoint, session, coordinator, intentHandler); }
    @finally { --sSettingsNavigationDepth; }
}

static id FBTNavigationInfo(id cls, SEL selector, UIViewController *controller,
                            NSUInteger method, NSUInteger options, id completion, id whenClosed) {
    if (sSettingsNavigationDepth && [controller isKindOfClass:[UIViewController class]]) {
        objc_setAssociatedObject(controller, &kFBTSettingsRootKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        FBTAddSettingsIcon(controller);
    }
    return sOriginalNavigationInfo(cls, selector, controller, method, options, completion, whenClosed);
}

static void FBTViewDidAppear(id object, SEL selector, BOOL animated) {
    sOriginalViewDidAppear(object, selector, animated);
    if (!objc_getAssociatedObject(object, &kFBTSettingsRootKey)) return;
    FBTAddSettingsIcon(object);
    // Bloks can update its navigation item while its appearance completes.
    __weak UIViewController *weakController = object;
    dispatch_async(dispatch_get_main_queue(), ^{ FBTAddSettingsIcon(weakController); });
}

static void FBTAttachGestureToWindow(UIWindow *window) {
    if (!window.rootViewController || window.windowLevel != UIWindowLevelNormal ||
        objc_getAssociatedObject(window, &kFBTWindowGestureKey)) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:[FBTEntryPointTarget shared] action:@selector(handleThreeFingerDoubleTap:)];
    tap.numberOfTouchesRequired = 3;
    tap.numberOfTapsRequired = 2;
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesBegan = NO;
    tap.delaysTouchesEnded = NO;
    tap.delegate = [FBTEntryPointTarget shared];
    [window addGestureRecognizer:tap];
    objc_setAssociatedObject(window, &kFBTWindowGestureKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void FBTRetryEntryPoints(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ FBTRetryEntryPoints(); });
        return;
    }
    Class info = objc_getClass("FBNavigationInfo");
    SEL selector = sel_registerName("infoWithViewController:method:options:completion:whenClosed:");
    Method method = info ? class_getClassMethod(info, selector) : NULL;
    if (!sOriginalNavigationInfo && method &&
        strcmp(method_getTypeEncoding(method), "@56@0:8@16Q24Q32@?40@?48") == 0) {
        MSHookMessageEx(object_getClass(info), selector, (IMP)FBTNavigationInfo,
                        (IMP *)&sOriginalNavigationInfo);
    }
    if (!sSettingsBindingRegistered && sOriginalNavigationInfo) {
        struct rebinding binding = { "FBSettingsControllerOpenBloksAction",
            (void *)FBTSettingsOpen, (void **)&sOriginalSettingsOpen };
        sSettingsBindingRegistered = (rebind_symbols(&binding, 1) == 0);
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) FBTAttachGestureToWindow(window);
    }
}

void FBTInstallEntryPoints(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        MSHookMessageEx([UIViewController class], @selector(viewDidAppear:),
                        (IMP)FBTViewDidAppear, (IMP *)&sOriginalViewDidAppear);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeKeyNotification,
                                  UIApplicationDidBecomeActiveNotification, UISceneDidActivateNotification,
                                  NSBundleDidLoadNotification]) {
            [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                            usingBlock:^(NSNotification *note) { FBTRetryEntryPoints(); }];
        }
    });
    dispatch_async(dispatch_get_main_queue(), ^{ FBTRetryEntryPoints(); });
}
