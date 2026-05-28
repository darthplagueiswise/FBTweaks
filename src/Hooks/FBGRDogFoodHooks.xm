// FBGRDogFoodHooks.xm — safe DogFood / Internal integration.
//
// Binary-confirmed items in Facebook(3) / FBSharedFramework(90):
//   _TtC11FBDogFoodUI17DogFoodController
//   + getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:
//   FBDogFood-managedPhoneFlag
//   FBAppJobDogFoodWarm / FBAppJobDogFoodCold
//   TB,R,N,V_enableDogfoodingView / _isDogfoodingView
//
// No global class scan here. The native UI is opened only from the menu action.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRLog.h"

static NSString * const kFBGRDogFoodMaster = @"fbgr_dogfood_master";

static void FBGRDogFoodWriteStandardDefaults(BOOL enabled) {
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setBool:enabled forKey:@"FBDogFood-managedPhoneFlag"];
    [std setBool:enabled forKey:@"FBDogFood-enableDogfoodingView"];
    [std setBool:enabled forKey:@"enableDogfoodingView"];
    [std synchronize];
}

static id FBGRDogFoodActiveSession(void) {
    Class sessionCls = NSClassFromString(@"FBUserSession");
    if (!sessionCls) return nil;
    for (NSString *name in @[
        @"activeSession",
        @"activeUserSession",
        @"currentSession",
        @"currentUserSession",
        @"mainSession",
        @"sharedSession",
        @"loggedInUserSession",
    ]) {
        SEL sel = NSSelectorFromString(name);
        if ([sessionCls respondsToSelector:sel]) {
            id obj = ((id(*)(id, SEL))objc_msgSend)(sessionCls, sel);
            if (obj) return obj;
        }
    }
    return nil;
}

static UIViewController *FBGRDogFoodNagSheet(void) {
    Class cls = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    if (!cls) return nil;

    SEL sel = NSSelectorFromString(@"getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");
    if (![cls respondsToSelector:sel]) return nil;

    id session = FBGRDogFoodActiveSession();
    if (!session) return nil;

    NSString *title    = @"Facebook DogFood";
    NSString *message  = @"Ativar modo DogFood / managed phone para liberar superfícies internas compatíveis.";
    NSString *switchTx = @"Ativar";
    NSString *snoozeTx = @"Depois";
    BOOL snoozeEnabled = YES;

    id onSwitch = [^(BOOL on) {
        [FBGRPrefs() setBool:on forKey:kFBGRDogFoodMaster];
        [FBGRPrefs() synchronize];
        FBGRDogFoodWriteStandardDefaults(on);
        FBGRLogAppend([NSString stringWithFormat:@"DogFood native switch -> %@", on ? @"ON" : @"OFF"]);
    } copy];
    id onSnooze = [^{ FBGRLogAppend(@"DogFood native snooze"); } copy];

    typedef id (*NagIMP)(id, SEL, id, id, id, id, id, BOOL, id, id);
    NagIMP imp = (NagIMP)[cls methodForSelector:sel];
    if (!imp) return nil;

    @try {
        id vc = imp(cls, sel, session, title, message, switchTx, snoozeTx, snoozeEnabled, onSwitch, onSnooze);
        return [vc isKindOfClass:UIViewController.class] ? (UIViewController *)vc : nil;
    } @catch (NSException *e) {
        FBGRLogAppend([NSString stringWithFormat:@"DogFood native exception: %@", e]);
        return nil;
    }
}

static UIViewController *FBGRTopPresenter(void) {
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

extern "C" BOOL FBGRDogFoodIsEnabled(void) {
    return [FBGRPrefs() boolForKey:kFBGRDogFoodMaster];
}

extern "C" void FBGRDogFoodSetEnabled(BOOL enabled) {
    [FBGRPrefs() setBool:enabled forKey:kFBGRDogFoodMaster];
    [FBGRPrefs() synchronize];
    FBGRDogFoodWriteStandardDefaults(enabled);
}

extern "C" BOOL FBGRDogFoodPresentNagSheet(void) {
    UIViewController *vc = FBGRDogFoodNagSheet();
    if (!vc) {
        FBGRLogAppend(@"DogFood native sheet unavailable: missing class, selector, session, or VC result");
        return NO;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = FBGRTopPresenter();
        if (top) [top presentViewController:vc animated:YES completion:nil];
    });
    return YES;
}

extern "C" NSString *FBGRDogFoodDiagnostic(void) {
    Class cls = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    SEL sel = NSSelectorFromString(@"getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");
    id session = FBGRDogFoodActiveSession();
    NSUserDefaults *std = NSUserDefaults.standardUserDefaults;
    return [NSString stringWithFormat:
        @"DogFoodController=%@\ngetNagSheet=%@\nFBUserSession=%@\nmaster=%@\nmanagedPhoneFlag=%@\nenableDogfoodingView=%@\nbundle=%@",
        cls ? NSStringFromClass(cls) : @"NOT FOUND",
        (cls && [cls respondsToSelector:sel]) ? @"YES" : @"NO",
        session ? NSStringFromClass([session class]) : @"NOT FOUND",
        FBGRDogFoodIsEnabled() ? @"ON" : @"OFF",
        [std boolForKey:@"FBDogFood-managedPhoneFlag"] ? @"YES" : @"NO",
        [std boolForKey:@"enableDogfoodingView"] ? @"YES" : @"NO",
        NSBundle.mainBundle.bundleIdentifier ?: @"unknown"];
}
