// FBGRDogFoodHooks.xm — Facebook DogFood internal menu hooks.
//
// O que o FBDogFoodUI contém (binary analysis v563.0.0):
//   _TtC11FBDogFoodUI17DogFoodController  ← Swift class, mangled ObjC name
//   Método de classe: getNagSheetWithSession:title:message:switchButtonText:
//                     snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:
//   UserDefaults keys:
//     FBDogFood-managedPhoneFlag       ← chave que ativa "managed phone" mode
//     FBDogFood-dismissClickCount
//     FBDogFood-lastSnoozedOnDismissDate
//     FBDogFood-lastSnoozedOnSwitchDate
//   App jobs:
//     FBAppJobDogFoodCold / FBAppJobDogFoodWarm
//   Outros:
//     TB,R,N,V_enableDogfoodingView  ← BOOL property "enableDogfoodingView"
//     _isDogfoodingView              ← C global ou selector
//     DogfoodNagSheetComponent       ← componente Bloks/RN
//     com.facebook.dogfood.internal  ← bundle identifier interno
//     autofill.action.UpdateMcDogfooding
//
// Hook strategy:
//   1. FBGRDogFoodEnabled() — lê pref e define estado "managed phone"
//   2. Inject "FBDogFood-managedPhoneFlag" = YES no NSUserDefaults standard
//      (isto é lido pelo app no FBAppJobDogFoodWarm startup job)
//   3. Expõe FBGRDogFoodPresentNagSheet() para o menu chamar o VC nativo

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRLog.h"

// ── Pref key ──────────────────────────────────────────────────────────────────
static NSString * const kFBGRDogFoodMaster = @"fbgr_dogfood_master";

// ── FBDogFood-managedPhoneFlag — ativa o dogfood mode da app ─────────────────
// Chave lida pelo FBAppJobDogFoodWarm/Cold no startup da app.
// Com YES, a app pensa que está num "Gold managed device" (employee phone).
static void FBGRDogFoodApplyManagedPhoneFlag(void) {
    BOOL enabled = [FBGRPrefs() boolForKey:kFBGRDogFoodMaster];
    // Esta chave vai no NSUserDefaults padrão do app (não na nossa suite)
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:@"FBDogFood-managedPhoneFlag"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    FBGRLogAppend([NSString stringWithFormat:
        @"DogFood: managedPhoneFlag = %@", enabled ? @"YES" : @"NO"]);
}

// ── FBDogFoodUI.DogFoodController ────────────────────────────────────────────
// Classe Swift — o nome ObjC mangled é _TtC11FBDogFoodUI17DogFoodController
// Logos resolve em runtime via objc_getClass.
// O método getNagSheetWithSession: retorna um UIViewController.
// A sessão (FBUserSession) é obtida via performSelector para evitar header.

static UIViewController *FBGRDogFoodNagSheet(void) {
    Class cls = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    if (!cls) {
        FBGRLogAppend(@"DogFood: DogFoodController class not found");
        return nil;
    }

    // getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:
    //                        snoozeEnabled:onSwitch:onSnooze:
    // Precisa de FBUserSession — obter via [FBUserSession activeSession]
    id session = nil;
    Class sessionCls = NSClassFromString(@"FBUserSession");
    if (sessionCls) {
        SEL activeSessionSel = NSSelectorFromString(@"activeSession");
        if ([sessionCls respondsToSelector:activeSessionSel]) {
            session = ((id(*)(id, SEL))objc_msgSend)(sessionCls, activeSessionSel);
        }
        if (!session) {
            // Fallback: activeUserSession
            SEL altSel = NSSelectorFromString(@"activeUserSession");
            if ([sessionCls respondsToSelector:altSel]) {
                session = ((id(*)(id, SEL))objc_msgSend)(sessionCls, altSel);
            }
        }
    }

    if (!session) {
        FBGRLogAppend(@"DogFood: FBUserSession not available — cannot create nag sheet");
        return nil;
    }

    SEL sel = NSSelectorFromString(
        @"getNagSheetWithSession:title:message:switchButtonText:"
        @"snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");

    if (![cls respondsToSelector:sel]) {
        FBGRLogAppend(@"DogFood: getNagSheetWithSession: not found");
        return nil;
    }

    // Parâmetros do nag sheet
    NSString *title    = @"FBTweaks DogFood";
    NSString *message  = @"Ativar modo dogfood (managed phone)?";
    NSString *switchTx = @"Ativar";
    NSString *snoozeTx = @"Mais tarde";
    BOOL snoozeEnabled = YES;

    id __block nagSheet = nil;
    id onSwitch = [^(BOOL on) {
        [FBGRPrefs() setBool:on forKey:kFBGRDogFoodMaster];
        FBGRDogFoodApplyManagedPhoneFlag();
        FBGRLogAppend([NSString stringWithFormat:@"DogFood: switch → %@", on ? @"ON" : @"OFF"]);
    } copy];
    id onSnooze = [^{
        FBGRLogAppend(@"DogFood: snoozed");
    } copy];

    typedef id (*NagIMP)(id, SEL, id, id, id, id, id, BOOL, id, id);
    NagIMP imp = (NagIMP)[cls methodForSelector:sel];
    @try {
        nagSheet = imp(cls, sel,
                       session, title, message,
                       switchTx, snoozeTx, snoozeEnabled,
                       onSwitch, onSnooze);
    } @catch (NSException *e) {
        FBGRLogAppend([NSString stringWithFormat:@"DogFood: exception %@", e]);
        return nil;
    }

    FBGRLogAppend([NSString stringWithFormat:
        @"DogFood: nagSheet created → %@", NSStringFromClass([nagSheet class])]);
    return (UIViewController *)nagSheet;
}

// ── Public API ────────────────────────────────────────────────────────────────
extern "C" BOOL FBGRDogFoodIsEnabled(void) {
    return [FBGRPrefs() boolForKey:kFBGRDogFoodMaster];
}

extern "C" void FBGRDogFoodSetEnabled(BOOL enabled) {
    [FBGRPrefs() setBool:enabled forKey:kFBGRDogFoodMaster];
    [FBGRPrefs() synchronize];
    FBGRDogFoodApplyManagedPhoneFlag();
}

extern "C" BOOL FBGRDogFoodPresentNagSheet(void) {
    UIViewController *vc = FBGRDogFoodNagSheet();
    if (!vc) return NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        // Find the top presenter
        UIViewController *top = nil;
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w.isKeyWindow) { top = w.rootViewController; break; }
            }
        }
        while (top.presentedViewController) top = top.presentedViewController;
        if (top) [top presentViewController:vc animated:YES completion:nil];
    });
    return YES;
}

extern "C" NSString *FBGRDogFoodDiagnostic(void) {
    Class cls = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    BOOL managedFlag = [[NSUserDefaults standardUserDefaults]
                         boolForKey:@"FBDogFood-managedPhoneFlag"];
    return [NSString stringWithFormat:
        @"DogFoodController=%@\nmaster=%@\nmanagedPhoneFlag=%@\nenableView=%@",
        cls ? NSStringFromClass(cls) : @"NOT FOUND",
        FBGRDogFoodIsEnabled() ? @"ON" : @"OFF",
        managedFlag ? @"YES" : @"NO",
        [[NSUserDefaults standardUserDefaults] boolForKey:@"FBDogFood-enableDogfoodingView"]
            ? @"YES" : @"NO"];
}

// ── Constructor ───────────────────────────────────────────────────────────────
__attribute__((constructor))
static void FBGRDogFoodCtor(void) {
    @autoreleasepool {
        // Apply managedPhoneFlag on every launch so the job picks it up
        FBGRDogFoodApplyManagedPhoneFlag();
        FBGRLogAppend(@"DogFood: ctor done");
    }
}
