// FBGRDogFoodHooks.xm — DogFood/Gold sheet + directed DLP/internal gates.
// No broad runtime enumeration. No arbitrary class_getInstanceMethod sweep.

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
static BOOL gDogFoodRuntimeEnabled = NO;
static BOOL gDirectedHooksInstalled = NO;
static NSUInteger gDirectedHookCount = 0;
static IMP gOrigDLPComponent = NULL;

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

static void FBGRDogFoodReloadRuntimeFlag(void) {
    gDogFoodRuntimeEnabled = [FBGRPrefs() boolForKey:kFBGRDogFoodMaster] ||
                              [NSUserDefaults.standardUserDefaults boolForKey:@"FBDogFood-managedPhoneFlag"];
}

static const uint64_t kDogFoodMCSlots[] = {
    161, 189, 286, 289, 292, 296, 298, 302, 305, 315, 317, 322,
    326, 329, 335, 337, 381, 546, 623, 816, 874, 1154, 1247,
    1263, 1271, 1498, 1618, 2028, 2742, 3092, 3103, 3110, 3142,
    3205, 3441, 3656, 3857, 4006, 4120, 4198, 4199, 4358, 4444,
    4452, 4536, 4620
};

static void FBGRDogFoodApplyMCOverrides(BOOL enabled) {
    for (NSUInteger i = 0; i < sizeof(kDogFoodMCSlots) / sizeof(kDogFoodMCSlots[0]); i++) {
        if (enabled) FBGRGateSet(kDogFoodMCSlots[i], YES);
        else FBGRGateClear(kDogFoodMCSlots[i]);
    }
    FBGRGateStoreWarmup();
    FBGRMCGateCacheRefresh();
    if (enabled) FBGRMCGateHooksEnsureInstalled();
}

static void FBGRDogFoodWriteDefaults(BOOL enabled) {
    NSUserDefaults *std = NSUserDefaults.standardUserDefaults;
    for (NSString *k in @[@"FBDogFood-managedPhoneFlag", @"FBDogFood-enableDogfoodingView", @"enableDogfoodingView", @"_isDogfoodingView", @"isDogfoodingView", @"FBDogFood-internal", @"FBInternalDogFood", @"is_dogfooding_enabled", @"is_in_switcher_company_dogfooding", @"is_dlp_native_dogfooding_component_enabled", @"ig_fb_dogfooder"]) {
        [std setBool:enabled forKey:k];
    }
    if (enabled) {
        [std removeObjectForKey:@"FBDogFood-lastSnoozedOnSwitchDate"];
        [std removeObjectForKey:@"FBDogFood-lastSnoozedOnDismissDate"];
        [std setInteger:0 forKey:@"FBDogFood-dismissClickCount"];
    }
    [std synchronize];
    gDogFoodRuntimeEnabled = enabled;
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

static BOOL FBGRLooksLikeSession(id obj) {
    if (!obj) return NO;
    Class c = NSClassFromString(@"FBUserSession");
    if (c && [obj isKindOfClass:c]) return YES;
    return [NSStringFromClass([obj class]) containsString:@"FBUserSession"];
}

static id FBGRSafeGetter(id obj, NSString *name) {
    if (!obj || !name.length) return nil;
    SEL sel = NSSelectorFromString(name);
    if (![obj respondsToSelector:sel]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(obj, sel); }
    @catch (__unused NSException *e) { return nil; }
}

static id FBGRSafeIvar(id obj, NSString *name) {
    if (!obj || !name.length) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name.UTF8String);
    if (!iv) return nil;
    @try { return object_getIvar(obj, iv); }
    @catch (__unused NSException *e) { return nil; }
}

static void FBGRDogFoodEnqueue(id obj, NSMutableArray *q, NSHashTable *seen, NSUInteger depth, NSString *src) {
    if (!obj || [seen containsObject:obj]) return;
    [seen addObject:obj];
    [q addObject:@{ @"obj": obj, @"depth": @(depth), @"src": src ?: NSStringFromClass([obj class]) ?: @"object" }];
}

static id FBGRSearchSession(id root, NSString *source, NSUInteger maxDepth) {
    if (!root) return nil;
    NSMutableArray *q = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    FBGRDogFoodEnqueue(root, q, seen, 0, source ?: NSStringFromClass([root class]));
    NSArray *getters = @[@"userSession", @"fbUserSession", @"session", @"currentSession", @"currentUserSession", @"activeSession", @"loggedInUserSession", @"userSessionIfAvailable", @"sessionIfAlreadyExists"];
    NSArray *ivars = @[@"_userSession", @"_fbUserSession", @"_session", @"userSession", @"fbUserSession", @"session"];
    while (q.count) {
        NSDictionary *e = q.firstObject; [q removeObjectAtIndex:0];
        id obj = e[@"obj"]; NSUInteger depth = [e[@"depth"] unsignedIntegerValue]; NSString *src = e[@"src"];
        if (FBGRLooksLikeSession(obj)) { gLastDogFoodSessionSource = src; return obj; }
        if (depth >= maxDepth) continue;
        for (NSString *n in getters) { id c = FBGRSafeGetter(obj, n); if (FBGRLooksLikeSession(c)) { gLastDogFoodSessionSource = [src stringByAppendingFormat:@".%@", n]; return c; } }
        for (NSString *n in ivars) { id c = FBGRSafeIvar(obj, n); if (FBGRLooksLikeSession(c)) { gLastDogFoodSessionSource = [src stringByAppendingFormat:@"->%@", n]; return c; } }
        if ([obj isKindOfClass:UIViewController.class]) {
            UIViewController *vc = obj;
            FBGRDogFoodEnqueue(vc.view, q, seen, depth + 1, [src stringByAppendingString:@".view"]);
            if (vc.navigationController) FBGRDogFoodEnqueue(vc.navigationController, q, seen, depth + 1, [src stringByAppendingString:@".navigationController"]);
            if (vc.tabBarController) FBGRDogFoodEnqueue(vc.tabBarController, q, seen, depth + 1, [src stringByAppendingString:@".tabBarController"]);
            if (vc.parentViewController) FBGRDogFoodEnqueue(vc.parentViewController, q, seen, depth + 1, [src stringByAppendingString:@".parent"]);
            if (vc.presentingViewController) FBGRDogFoodEnqueue(vc.presentingViewController, q, seen, depth + 1, [src stringByAppendingString:@".presenting"]);
            if (vc.presentedViewController) FBGRDogFoodEnqueue(vc.presentedViewController, q, seen, depth + 1, [src stringByAppendingString:@".presented"]);
            for (UIViewController *ch in vc.childViewControllers) FBGRDogFoodEnqueue(ch, q, seen, depth + 1, [src stringByAppendingFormat:@".child(%@)", NSStringFromClass([ch class])]);
        } else if ([obj isKindOfClass:UIWindow.class]) {
            UIWindow *w = obj; if (w.rootViewController) FBGRDogFoodEnqueue(w.rootViewController, q, seen, depth + 1, [src stringByAppendingString:@".root"]);
        } else if ([obj isKindOfClass:UIView.class]) {
            UIView *v = obj;
            if (v.nextResponder) FBGRDogFoodEnqueue(v.nextResponder, q, seen, depth + 1, [src stringByAppendingString:@".nextResponder"]);
            if (v.superview) FBGRDogFoodEnqueue(v.superview, q, seen, depth + 1, [src stringByAppendingString:@".superview"]);
        }
    }
    return nil;
}

static id FBGRDogFoodActiveSession(void) {
    gLastDogFoodSessionSource = nil;
    Class c = NSClassFromString(@"FBUserSession");
    for (NSString *n in @[@"activeSession", @"activeUserSession", @"currentSession", @"currentUserSession", @"sharedSession", @"defaultSession"]) {
        if (c && [c respondsToSelector:NSSelectorFromString(n)]) {
            id s = FBGRSafeGetter(c, n); if (FBGRLooksLikeSession(s)) { gLastDogFoodSessionSource = [@"FBUserSession +" stringByAppendingString:n]; return s; }
        }
    }
    UIViewController *top = FBGRDogFoodTopPresenter();
    id s = FBGRSearchSession(top, NSStringFromClass([top class]), 5);
    if (s) return s;
    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) if ([sc isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)sc).windows) { s = FBGRSearchSession(w, NSStringFromClass([w class]), 5); if (s) return s; }
    }
    return nil;
}

static Class FBGRDogFoodControllerClass(void) {
    Class cls = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    if (!cls) cls = NSClassFromString(@"FBDogFoodUI.DogFoodController");
    if (!cls) cls = objc_getClass("_TtC11FBDogFoodUI17DogFoodController");
    return cls;
}

static Class FBGRDLPProviderClass(void) {
    Class cls = NSClassFromString(@"FBDLPDogfoodingIndicator.FBDLPDogfoodingIndicatorProvider");
    if (!cls) cls = NSClassFromString(@"_TtC24FBDLPDogfoodingIndicator32FBDLPDogfoodingIndicatorProvider");
    if (!cls) cls = objc_getClass("_TtC24FBDLPDogfoodingIndicator32FBDLPDogfoodingIndicatorProvider");
    return cls;
}

typedef id (*DLPComponentIMP)(id, SEL, id, id);
static id FBGRDLPComponentHook(id self, SEL _cmd, id label, id session) {
    DLPComponentIMP orig = (DLPComponentIMP)gOrigDLPComponent;
    if (!orig) return nil;
    if (!(gDogFoodRuntimeEnabled || [FBGRPrefs() boolForKey:kFBGRDogFoodMaster])) return orig(self, _cmd, label, session);
    id result = orig(self, _cmd, label ?: @"DOGFOOD", session);
    if (!result) result = orig(self, _cmd, @"DogFood", session);
    return result;
}

extern "C" void FBGRDogFoodInstallDirectedHooks(void) {
    if (gDirectedHooksInstalled) return;
    gDirectedHooksInstalled = YES;
    Class dlp = FBGRDLPProviderClass();
    SEL sel = NSSelectorFromString(@"componentWithLabel:session:");
    if (dlp && [dlp respondsToSelector:sel]) {
        MSHookMessageEx(object_getClass(dlp), sel, (IMP)FBGRDLPComponentHook, (IMP *)&gOrigDLPComponent);
        if (gOrigDLPComponent) gDirectedHookCount++;
    }
    FBGRLogAppend([NSString stringWithFormat:@"DogFood directed hooks=%lu dlp=%@", (unsigned long)gDirectedHookCount, dlp ? NSStringFromClass(dlp) : @"NOT FOUND"]);
}

extern "C" void FBGRDogFoodApplyPersistentState(void) {
    FBGRDogFoodReloadRuntimeFlag();
    if (!gDogFoodRuntimeEnabled) return;
    FBGRDogFoodWriteDefaults(YES);
    FBGRDogFoodApplyMCOverrides(YES);
    FBGRDogFoodInstallDirectedHooks();
}

extern "C" BOOL FBGRDogFoodIsEnabled(void) { return [FBGRPrefs() boolForKey:kFBGRDogFoodMaster]; }

extern "C" void FBGRDogFoodSetEnabled(BOOL enabled) {
    [FBGRPrefs() setBool:enabled forKey:kFBGRDogFoodMaster];
    [FBGRPrefs() synchronize];
    FBGRDogFoodWriteDefaults(enabled);
    FBGRDogFoodApplyMCOverrides(enabled);
    if (enabled) FBGRDogFoodInstallDirectedHooks();
}

static UIViewController *FBGRDogFoodNagSheet(void) {
    gLastDogFoodFailure = nil;
    Class cls = FBGRDogFoodControllerClass();
    SEL sel = NSSelectorFromString(@"getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");
    if (!cls) { gLastDogFoodFailure = @"DogFoodController class not found"; return nil; }
    if (![cls respondsToSelector:sel]) { gLastDogFoodFailure = @"getNagSheet selector not found"; return nil; }
    id session = FBGRDogFoodActiveSession();
    if (!session) { gLastDogFoodFailure = @"FBUserSession not found"; return nil; }
    id onSwitch = [^{ FBGRDogFoodSetEnabled(YES); FBGRDogFoodApplyPersistentState(); } copy];
    id onSnooze = [^{ FBGRLogAppend(@"DogFood native snooze"); } copy];
    typedef id (*NagIMP)(id, SEL, id, id, id, id, id, BOOL, id, id);
    NagIMP imp = (NagIMP)[cls methodForSelector:sel];
    @try {
        id result = imp(cls, sel, session, @"Facebook DogFood", @"Ativa managedPhoneFlag, MC gates Employee/Internal e hook direcionado DLP.", @"Ativar", @"Depois", YES, onSwitch, onSnooze);
        if ([result isKindOfClass:UIViewController.class]) return result;
        gLastDogFoodFailure = result ? [NSString stringWithFormat:@"native result %@ is not VC", NSStringFromClass([result class])] : @"native result nil";
        return nil;
    } @catch (NSException *e) { gLastDogFoodFailure = e.reason ?: e.name; return nil; }
}

extern "C" BOOL FBGRDogFoodPresentNagSheet(void) {
    __block UIViewController *vc = nil;
    if ([NSThread isMainThread]) vc = FBGRDogFoodNagSheet();
    else dispatch_sync(dispatch_get_main_queue(), ^{ vc = FBGRDogFoodNagSheet(); });
    if (!vc) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ UIViewController *top = FBGRDogFoodTopPresenter(); if (top) [top presentViewController:vc animated:YES completion:nil]; });
    return YES;
}

extern "C" NSString *FBGRDogFoodDiagnostic(void) {
    Class cls = FBGRDogFoodControllerClass();
    SEL nagSel = NSSelectorFromString(@"getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");
    Class dlp = FBGRDLPProviderClass();
    SEL compSel = NSSelectorFromString(@"componentWithLabel:session:");
    id session = FBGRDogFoodActiveSession();
    NSUserDefaults *std = NSUserDefaults.standardUserDefaults;
    return [NSString stringWithFormat:@"DogFoodController=%@\ngetNagSheet=%@\nFBUserSession=%@\nsessionSource=%@\nlastFailure=%@\nmaster=%@\nmanagedPhoneFlag=%@\nenableDogfoodingView=%@\nruntimeEnabled=%@\ndirectedHooks=%lu\ndlpClass=%@\ndlpComponent=%@\nbundle=%@",
        cls ? NSStringFromClass(cls) : @"NOT FOUND", (cls && [cls respondsToSelector:nagSel]) ? @"YES" : @"NO", session ? NSStringFromClass([session class]) : @"NOT FOUND", gLastDogFoodSessionSource ?: @"n/a", gLastDogFoodFailure ?: @"n/a", FBGRDogFoodIsEnabled() ? @"ON" : @"OFF", [std boolForKey:@"FBDogFood-managedPhoneFlag"] ? @"YES" : @"NO", [std boolForKey:@"enableDogfoodingView"] ? @"YES" : @"NO", gDogFoodRuntimeEnabled ? @"YES" : @"NO", (unsigned long)gDirectedHookCount, dlp ? NSStringFromClass(dlp) : @"NOT FOUND", (dlp && [dlp respondsToSelector:compSel]) ? @"YES" : @"NO", NSBundle.mainBundle.bundleIdentifier ?: @"unknown"];
}

%hook NSUserDefaults
- (BOOL)boolForKey:(NSString *)defaultName { if (gDogFoodRuntimeEnabled && FBGRDogFoodKeyIsManaged(defaultName)) return YES; return %orig; }
- (id)objectForKey:(NSString *)defaultName { if (gDogFoodRuntimeEnabled && FBGRDogFoodKeyIsManaged(defaultName)) return @YES; return %orig; }
- (id)valueForKey:(NSString *)key { if (gDogFoodRuntimeEnabled && FBGRDogFoodKeyIsManaged(key)) return @YES; return %orig; }
%end

%ctor {
    @autoreleasepool {
        FBGRDogFoodReloadRuntimeFlag();
        if (gDogFoodRuntimeEnabled) {
            FBGRDogFoodWriteDefaults(YES);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ FBGRDogFoodInstallDirectedHooks(); });
        }
    }
}
