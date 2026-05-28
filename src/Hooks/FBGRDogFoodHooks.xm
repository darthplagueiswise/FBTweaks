// FBGRDogFoodHooks.xm — safe DogFood / Internal integration.
//
// Binary-confirmed items in Facebook(3) / FBSharedFramework(90):
//   _TtC11FBDogFoodUI17DogFoodController
//   FBDogFoodUI.DogFoodController (runtime/FLEX display name)
//   + getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:
//   FBDogFood-managedPhoneFlag
//   FBAppJobDogFoodWarm / FBAppJobDogFoodCold
//   TB,R,N,V_enableDogfoodingView / _isDogfoodingView
//
// Important: the native sheet needs a real FBUserSession. There is no stable
// public class method such as +activeSession on all Facebook builds, so the
// resolver below walks the currently visible VC/window graph and pulls the
// session from userSession/fbUserSession/session properties or ivars.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRLog.h"
#import "../Runtime/FBGRGateStore.h"

extern "C" void FBGRMCGateHooksEnsureInstalled(void);
extern "C" void FBGRMCGateCacheRefresh(void);

static NSString * const kFBGRDogFoodMaster = @"fbgr_dogfood_master";
static NSString *gLastDogFoodSessionSource = nil;
static NSString *gLastDogFoodFailure = nil;
static BOOL gFBGRDogFoodRuntimeEnabled = NO;
static BOOL gFBGRDogFoodBoolMethodHooksInstalled = NO;
static NSUInteger gFBGRDogFoodBoolMethodHooked = 0;

static BOOL FBGRDogFoodKeyIsManaged(NSString *key) {
    if (![key isKindOfClass:NSString.class]) return NO;
    return [key isEqualToString:@"FBDogFood-managedPhoneFlag"] ||
           [key isEqualToString:@"FBDogFood-enableDogfoodingView"] ||
           [key isEqualToString:@"enableDogfoodingView"] ||
           [key isEqualToString:@"_isDogfoodingView"] ||
           [key isEqualToString:@"isDogfoodingView"] ||
           [key isEqualToString:@"FBDogFood-internal"] ||
           [key isEqualToString:@"FBInternalDogFood"] ||
           [key isEqualToString:@"com.facebook.dogfood.internal"] ||
           [key isEqualToString:@"ig_fb_dogfooder"] ||
           [key isEqualToString:@"is_dogfooding_enabled"] ||
           [key isEqualToString:@"is_in_switcher_company_dogfooding"] ||
           [key isEqualToString:@"is_dlp_native_dogfooding_component_enabled"] ||
           [key isEqualToString:@"FBDLPDogfoodingIndicator"] ||
           [key isEqualToString:@"zero-dogfood-device-id"];
}

static void FBGRDogFoodRuntimeReload(void) {
    gFBGRDogFoodRuntimeEnabled = [FBGRPrefs() boolForKey:kFBGRDogFoodMaster] ||
                                  [NSUserDefaults.standardUserDefaults boolForKey:@"FBDogFood-managedPhoneFlag"];
}


// MobileConfig slots derived from ReactMobileConfigMetadata.json and binary dogfood strings.
// These are normal MC bool gates related to dogfooding/internal/employee surfaces.
static const uint64_t kFBGRDogFoodMCSlots[] = {
    161, 189, 286, 289, 292, 296, 298, 302, 305, 315, 317, 322,
    326, 329, 335, 337, 381, 546, 623, 816, 874, 1154, 1247,
    1263, 1271, 1498, 1618, 2028, 2742, 3092, 3103, 3110, 3142,
    3205, 3441, 3656, 3857, 4006, 4120, 4198, 4199, 4358, 4444,
    4452, 4536, 4620
};

static void FBGRDogFoodApplyMCOverrides(BOOL enabled) {
    for (NSUInteger i = 0; i < sizeof(kFBGRDogFoodMCSlots) / sizeof(kFBGRDogFoodMCSlots[0]); i++) {
        uint64_t slot = kFBGRDogFoodMCSlots[i];
        if (enabled) FBGRGateSet(slot, YES);
        else FBGRGateClear(slot);
    }
    FBGRGateStoreWarmup();
    FBGRMCGateCacheRefresh();
    if (enabled) FBGRMCGateHooksEnsureInstalled();
}


extern "C" void FBGRDogFoodSetEnabled(BOOL enabled);
extern "C" void FBGRDogFoodApplyPersistentState(void);

static void FBGRDogFoodWriteStandardDefaults(BOOL enabled) {
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setBool:enabled forKey:@"FBDogFood-managedPhoneFlag"];
    [std setBool:enabled forKey:@"FBDogFood-enableDogfoodingView"];
    [std setBool:enabled forKey:@"enableDogfoodingView"];
    [std setBool:enabled forKey:@"_isDogfoodingView"];
    [std setBool:enabled forKey:@"isDogfoodingView"];
    [std setBool:enabled forKey:@"FBDogFood-internal"];
    [std setBool:enabled forKey:@"FBInternalDogFood"];
    [std setBool:enabled forKey:@"is_dogfooding_enabled"];
    [std setBool:enabled forKey:@"is_in_switcher_company_dogfooding"];
    [std setBool:enabled forKey:@"is_dlp_native_dogfooding_component_enabled"];
    [std setBool:enabled forKey:@"ig_fb_dogfooder"];
    if (enabled) {
        [std removeObjectForKey:@"FBDogFood-lastSnoozedOnSwitchDate"];
        [std removeObjectForKey:@"FBDogFood-lastSnoozedOnDismissDate"];
        [std setInteger:0 forKey:@"FBDogFood-dismissClickCount"];
    }
    [std synchronize];
    gFBGRDogFoodRuntimeEnabled = enabled;
}

static BOOL FBGRDogFoodLooksLikeSession(id obj) {
    if (!obj) return NO;
    Class sessionCls = NSClassFromString(@"FBUserSession");
    if (sessionCls && [obj isKindOfClass:sessionCls]) return YES;
    NSString *cn = NSStringFromClass([obj class]);
    return [cn containsString:@"FBUserSession"] || [cn isEqualToString:@"FBUserSession"];
}

static id FBGRSafeObjectGetter(id obj, NSString *selName) {
    if (!obj || selName.length == 0) return nil;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return nil;
    @try {
        id (*msg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        return msg(obj, sel);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static id FBGRSafeIvarObject(id obj, NSString *ivarName) {
    if (!obj || ivarName.length == 0) return nil;
    Ivar iv = class_getInstanceVariable([obj class], ivarName.UTF8String);
    if (!iv) return nil;
    @try { return object_getIvar(obj, iv); }
    @catch (__unused NSException *e) { return nil; }
}

static UIViewController *FBGRDogFoodTopPresenter(void) {
    UIViewController *top = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w.isKeyWindow && w.rootViewController) { top = w.rootViewController; break; }
            }
            if (top) break;
        }
    }
    if (!top) top = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:UINavigationController.class]) top = ((UINavigationController *)top).visibleViewController ?: top;
    if ([top isKindOfClass:UITabBarController.class]) top = ((UITabBarController *)top).selectedViewController ?: top;
    return top;
}

static NSArray *FBGRDogFoodSeedObjects(void) {
    NSMutableArray *seeds = [NSMutableArray array];
    UIViewController *top = FBGRDogFoodTopPresenter();
    if (top) [seeds addObject:top];

    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w) [seeds addObject:w];
                if (w.rootViewController) [seeds addObject:w.rootViewController];
            }
        }
    } else {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (w) [seeds addObject:w];
            if (w.rootViewController) [seeds addObject:w.rootViewController];
        }
    }
    return seeds;
}

static void FBGRDogFoodEnqueue(id obj, NSMutableArray *queue, NSHashTable *seen, NSUInteger depth, NSString *src) {
    if (!obj) return;
    @try {
        if (![obj isKindOfClass:NSObject.class]) return;
    } @catch (__unused NSException *e) {
        return;
    }
    if ([seen containsObject:obj]) return;
    [seen addObject:obj];
    NSString *safeSrc = src.length ? src : NSStringFromClass([obj class]);
    [queue addObject:@{ @"obj": obj, @"depth": @(depth), @"src": safeSrc ?: @"object" }];
}

static id FBGRDogFoodSearchObjectForSession(id root, NSString *sourcePrefix, NSUInteger maxDepth) {
    if (!root) return nil;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:@{ @"obj": root, @"depth": @0, @"src": sourcePrefix ?: @"root" }];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    [seen addObject:root];

    NSArray<NSString *> *getterNames = @[
        @"userSession", @"fbUserSession", @"session", @"currentSession",
        @"currentUserSession", @"activeSession", @"loggedInUserSession",
        @"userSessionIfAvailable", @"sessionIfAlreadyExists"
    ];
    NSArray<NSString *> *ivarNames = @[
        @"_userSession", @"_fbUserSession", @"_session", @"userSession", @"fbUserSession", @"session"
    ];

    while (queue.count) {
        id entry = queue.firstObject;
        [queue removeObjectAtIndex:0];
        id obj = nil;
        NSUInteger depth = 0;
        NSString *src = @"entry";
        if ([entry isKindOfClass:NSDictionary.class]) {
            NSDictionary *dict = (NSDictionary *)entry;
            obj = dict[@"obj"];
            depth = [dict[@"depth"] unsignedIntegerValue];
            src = dict[@"src"] ?: @"entry";
        } else {
            obj = entry;
            src = NSStringFromClass([obj class]) ?: @"rawEntry";
        }

        if (FBGRDogFoodLooksLikeSession(obj)) {
            gLastDogFoodSessionSource = src;
            return obj;
        }
        if (depth >= maxDepth) continue;

        for (NSString *name in getterNames) {
            id candidate = FBGRSafeObjectGetter(obj, name);
            if (FBGRDogFoodLooksLikeSession(candidate)) {
                gLastDogFoodSessionSource = [NSString stringWithFormat:@"%@.%@", src, name];
                return candidate;
            }
        }
        for (NSString *name in ivarNames) {
            id candidate = FBGRSafeIvarObject(obj, name);
            if (FBGRDogFoodLooksLikeSession(candidate)) {
                gLastDogFoodSessionSource = [NSString stringWithFormat:@"%@->%@", src, name];
                return candidate;
            }
        }

        if ([obj isKindOfClass:UIViewController.class]) {
            UIViewController *vc = obj;
            FBGRDogFoodEnqueue(vc.view, queue, seen, depth + 1, [src stringByAppendingString:@".view"]);
            if (vc.navigationController) FBGRDogFoodEnqueue(vc.navigationController, queue, seen, depth + 1, [src stringByAppendingString:@".navigationController"]);
            if (vc.tabBarController) FBGRDogFoodEnqueue(vc.tabBarController, queue, seen, depth + 1, [src stringByAppendingString:@".tabBarController"]);
            if (vc.parentViewController) FBGRDogFoodEnqueue(vc.parentViewController, queue, seen, depth + 1, [src stringByAppendingString:@".parentViewController"]);
            if (vc.presentingViewController) FBGRDogFoodEnqueue(vc.presentingViewController, queue, seen, depth + 1, [src stringByAppendingString:@".presentingViewController"]);
            if (vc.presentedViewController) FBGRDogFoodEnqueue(vc.presentedViewController, queue, seen, depth + 1, [src stringByAppendingString:@".presentedViewController"]);
            for (UIViewController *child in vc.childViewControllers) FBGRDogFoodEnqueue(child, queue, seen, depth + 1, [src stringByAppendingFormat:@".child(%@)", NSStringFromClass([child class])]);
        } else if ([obj isKindOfClass:UIView.class]) {
            UIView *v = obj;
            if (v.nextResponder) FBGRDogFoodEnqueue(v.nextResponder, queue, seen, depth + 1, [src stringByAppendingString:@".nextResponder"]);
            if (v.superview) FBGRDogFoodEnqueue(v.superview, queue, seen, depth + 1, [src stringByAppendingString:@".superview"]);
            for (UIView *sub in v.subviews) FBGRDogFoodEnqueue(sub, queue, seen, depth + 1, [src stringByAppendingFormat:@".subview(%@)", NSStringFromClass([sub class])]);
        } else if ([obj isKindOfClass:UIWindow.class]) {
            UIWindow *w = obj;
            if (w.rootViewController) FBGRDogFoodEnqueue(w.rootViewController, queue, seen, depth + 1, [src stringByAppendingString:@".rootViewController"]);
        }

        // Keep only cheap object graph sources. Do not enumerate every ivar of every object;
        // that is exactly the kind of broad runtime sweep that made previous builds fragile.
    }
    return nil;
}

static id FBGRDogFoodClassSessionFallback(void) {
    Class sessionCls = NSClassFromString(@"FBUserSession");
    if (!sessionCls) return nil;
    for (NSString *name in @[
        @"activeSession", @"activeUserSession", @"currentSession", @"currentUserSession",
        @"mainSession", @"sharedSession", @"loggedInUserSession", @"defaultSession"
    ]) {
        SEL sel = NSSelectorFromString(name);
        if ([sessionCls respondsToSelector:sel]) {
            id obj = nil;
            @try { obj = ((id(*)(id, SEL))objc_msgSend)(sessionCls, sel); } @catch (__unused NSException *e) {}
            if (FBGRDogFoodLooksLikeSession(obj)) {
                gLastDogFoodSessionSource = [NSString stringWithFormat:@"FBUserSession +%@", name];
                return obj;
            }
        }
    }
    return nil;
}

static id FBGRDogFoodActiveSession(void) {
    gLastDogFoodSessionSource = nil;
    id clsSession = FBGRDogFoodClassSessionFallback();
    if (clsSession) return clsSession;

    for (id seed in FBGRDogFoodSeedObjects()) {
        id s = FBGRDogFoodSearchObjectForSession(seed, NSStringFromClass([seed class]), 5);
        if (s) return s;
    }
    return nil;
}

static Class FBGRDogFoodControllerClass(void) {
    Class cls = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    if (!cls) cls = NSClassFromString(@"FBDogFoodUI.DogFoodController");
    if (!cls) cls = objc_getClass("_TtC11FBDogFoodUI17DogFoodController");
    return cls;
}

static UIViewController *FBGRDogFoodNagSheet(void) {
    gLastDogFoodFailure = nil;
    Class cls = FBGRDogFoodControllerClass();
    if (!cls) { gLastDogFoodFailure = @"DogFoodController class not found"; return nil; }

    SEL sel = NSSelectorFromString(@"getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");
    if (![cls respondsToSelector:sel]) { gLastDogFoodFailure = @"getNagSheet selector not found"; return nil; }

    id session = FBGRDogFoodActiveSession();
    if (!session) { gLastDogFoodFailure = @"FBUserSession not found in visible VC/window graph"; return nil; }

    NSString *title    = @"Facebook DogFood";
    NSString *message  = @"Ativar modo DogFood / managed phone para liberar superfícies internas compatíveis.";
    NSString *switchTx = @"Ativar";
    NSString *snoozeTx = @"Depois";
    BOOL snoozeEnabled = YES;

    id onSwitch = [^{
        FBGRDogFoodSetEnabled(YES);
        FBGRDogFoodApplyPersistentState();
        FBGRLogAppend(@"DogFood native activate -> ON");
    } copy];
    id onSnooze = [^{ FBGRLogAppend(@"DogFood native snooze"); } copy];

    typedef id (*NagIMP)(id, SEL, id, id, id, id, id, BOOL, id, id);
    NagIMP imp = (NagIMP)[cls methodForSelector:sel];
    if (!imp) { gLastDogFoodFailure = @"methodForSelector returned NULL"; return nil; }

    @try {
        id result = imp(cls, sel, session, title, message, switchTx, snoozeTx, snoozeEnabled, onSwitch, onSnooze);
        if ([result isKindOfClass:UIViewController.class]) return (UIViewController *)result;
        if (result) gLastDogFoodFailure = [NSString stringWithFormat:@"native result is %@, not UIViewController", NSStringFromClass([result class])];
        else gLastDogFoodFailure = @"native method returned nil";
        return nil;
    } @catch (NSException *e) {
        gLastDogFoodFailure = [NSString stringWithFormat:@"native exception: %@", e.reason ?: e.name];
        FBGRLogAppend([NSString stringWithFormat:@"DogFood native exception: %@", e]);
        return nil;
    }
}


typedef BOOL (*FBGRDogFoodBoolGetterIMP)(id, SEL);
static BOOL FBGRDogFoodBoolAlwaysYes(id self, SEL _cmd) {
    if (gFBGRDogFoodRuntimeEnabled || [FBGRPrefs() boolForKey:kFBGRDogFoodMaster]) return YES;
    return YES;
}

static void FBGRDogFoodHookBoolMethod(Class cls, SEL sel) {
    if (!cls || !sel || !class_getInstanceMethod(cls, sel)) return;
    IMP orig = NULL;
    MSHookMessageEx(cls, sel, (IMP)FBGRDogFoodBoolAlwaysYes, &orig);
    gFBGRDogFoodBoolMethodHooked++;
}

static void FBGRDogFoodInstallBoolMethodHooks(void) {
    if (gFBGRDogFoodBoolMethodHooksInstalled) return;
    gFBGRDogFoodBoolMethodHooksInstalled = YES;

    SEL enableSel = sel_registerName("enableDogfoodingView");
    SEL isSel = sel_registerName("_isDogfoodingView");
    SEL managedSel = sel_registerName("isManagedPhone");
    SEL dogfoodSel = sel_registerName("isDogfoodingEnabled");

    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        FBGRDogFoodHookBoolMethod(cls, enableSel);
        FBGRDogFoodHookBoolMethod(cls, isSel);
        FBGRDogFoodHookBoolMethod(cls, managedSel);
        FBGRDogFoodHookBoolMethod(cls, dogfoodSel);
    }
    free(classes);
    FBGRLogAppend([NSString stringWithFormat:@"DogFood bool hooks installed=%lu", (unsigned long)gFBGRDogFoodBoolMethodHooked]);
}

extern "C" void FBGRDogFoodApplyPersistentState(void) {
    FBGRDogFoodRuntimeReload();
    if (!gFBGRDogFoodRuntimeEnabled) return;
    FBGRDogFoodWriteStandardDefaults(YES);
    FBGRDogFoodApplyMCOverrides(YES);
    FBGRDogFoodInstallBoolMethodHooks();
}

extern "C" BOOL FBGRDogFoodIsEnabled(void) {
    return [FBGRPrefs() boolForKey:kFBGRDogFoodMaster];
}

extern "C" void FBGRDogFoodSetEnabled(BOOL enabled) {
    [FBGRPrefs() setBool:enabled forKey:kFBGRDogFoodMaster];
    [FBGRPrefs() synchronize];
    FBGRDogFoodWriteStandardDefaults(enabled);
    FBGRDogFoodApplyMCOverrides(enabled);
    if (enabled) FBGRDogFoodInstallBoolMethodHooks();
}

extern "C" BOOL FBGRDogFoodPresentNagSheet(void) {
    __block UIViewController *vc = nil;
    if ([NSThread isMainThread]) {
        vc = FBGRDogFoodNagSheet();
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{ vc = FBGRDogFoodNagSheet(); });
    }
    if (!vc) {
        FBGRLogAppend([NSString stringWithFormat:@"DogFood native sheet unavailable: %@", gLastDogFoodFailure ?: @"unknown"]);
        return NO;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = FBGRDogFoodTopPresenter();
        if (top) [top presentViewController:vc animated:YES completion:nil];
    });
    return YES;
}

extern "C" NSString *FBGRDogFoodDiagnostic(void) {
    Class cls = FBGRDogFoodControllerClass();
    SEL sel = NSSelectorFromString(@"getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");
    id session = FBGRDogFoodActiveSession();
    NSUserDefaults *std = NSUserDefaults.standardUserDefaults;
    UIViewController *top = FBGRDogFoodTopPresenter();
    return [NSString stringWithFormat:
        @"DogFoodController=%@\ngetNagSheet=%@\nFBUserSession=%@\nsessionSource=%@\ntopPresenter=%@\nlastFailure=%@\nmaster=%@\nmanagedPhoneFlag=%@\nenableDogfoodingView=%@\nruntimeEnabled=%@\nboolHooks=%lu\nbundle=%@",
        cls ? NSStringFromClass(cls) : @"NOT FOUND",
        (cls && [cls respondsToSelector:sel]) ? @"YES" : @"NO",
        session ? NSStringFromClass([session class]) : @"NOT FOUND",
        gLastDogFoodSessionSource ?: @"n/a",
        top ? NSStringFromClass([top class]) : @"NOT FOUND",
        gLastDogFoodFailure ?: @"n/a",
        FBGRDogFoodIsEnabled() ? @"ON" : @"OFF",
        [std boolForKey:@"FBDogFood-managedPhoneFlag"] ? @"YES" : @"NO",
        [std boolForKey:@"enableDogfoodingView"] ? @"YES" : @"NO",
        gFBGRDogFoodRuntimeEnabled ? @"YES" : @"NO",
        (unsigned long)gFBGRDogFoodBoolMethodHooked,
        NSBundle.mainBundle.bundleIdentifier ?: @"unknown"];
}


%hook NSUserDefaults

- (BOOL)boolForKey:(NSString *)defaultName {
    if (gFBGRDogFoodRuntimeEnabled && FBGRDogFoodKeyIsManaged(defaultName)) return YES;
    return %orig;
}

- (id)objectForKey:(NSString *)defaultName {
    if (gFBGRDogFoodRuntimeEnabled && FBGRDogFoodKeyIsManaged(defaultName)) return @YES;
    return %orig;
}

- (id)valueForKey:(NSString *)key {
    if (gFBGRDogFoodRuntimeEnabled && FBGRDogFoodKeyIsManaged(key)) return @YES;
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
        FBGRDogFoodRuntimeReload();
        if (gFBGRDogFoodRuntimeEnabled) {
            FBGRDogFoodWriteStandardDefaults(YES);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                FBGRDogFoodInstallBoolMethodHooks();
            });
        }
    }
}
