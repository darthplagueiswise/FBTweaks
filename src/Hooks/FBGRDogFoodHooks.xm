// FBGRDogFoodHooks.xm — DogFood/Employee/Internal/DLP integration.
//
// REWRITE per diagnosis:
//   • DogFoodController is ONLY a nag/install flow for the Gold "managed phone"
//     app. Setting FBDogFood-managedPhoneFlag does NOT unlock internal surfaces.
//     We keep it but label it honestly as "abrir nag nativo".
//   • Real employee/internal unlock = forcing MC slots (handled by GateRegistry
//     employee category + MCGateHooks) and a TARGETED DLP indicator hook.
//   • NO global object-graph / view-hierarchy scan (that caused the crash). The
//     session for the nag is fetched lazily and defensively, with try/catch and
//     respondsToSelector — never a BFS over the whole UI tree.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "../FBGramPrefix.h"
#import "../Runtime/FBGRLog.h"

static NSString * const kFBGRDogFoodMaster = @"fbgr_dogfood_master";
static NSString * const kFBGRDLPIndicator  = @"fbgr_dlp_indicator";

// ── managed-phone flag (honest: only marks device as managed) ─────────────────
static void FBGRDogFoodApplyManagedFlag(void) {
    BOOL on = [FBGRPrefs() boolForKey:kFBGRDogFoodMaster];
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"FBDogFood-managedPhoneFlag"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    FBGRLogAppend([NSString stringWithFormat:@"DogFood: managedPhoneFlag=%@", on?@"Y":@"N"]);
}

// ── Lazy, defensive session lookup (NO global scan) ───────────────────────────
// Only tries documented class entry points. Returns nil quietly on failure.
static id FBGRActiveUserSession(void) {
    Class cls = NSClassFromString(@"FBUserSession");
    if (!cls) return nil;
    for (NSString *selName in @[@"activeSession", @"activeUserSession", @"currentUserSession"]) {
        SEL sel = NSSelectorFromString(selName);
        if ([cls respondsToSelector:sel]) {
            @try {
                id s = ((id(*)(id,SEL))objc_msgSend)(cls, sel);
                if (s) return s;
            } @catch (__unused NSException *e) {}
        }
    }
    return nil;
}

static UIViewController *FBGRTopVC(void) {
    UIViewController *top = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows)
            if (w.isKeyWindow) { top = w.rootViewController; break; }
    }
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

// ── DogFood native nag sheet (honest entry point) ─────────────────────────────
extern "C" BOOL FBGRDogFoodPresentNagSheet(void) {
    Class cls = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    if (!cls) { FBGRLogAppend(@"DogFood: controller class missing"); return NO; }

    SEL sel = NSSelectorFromString(
        @"getNagSheetWithSession:title:message:switchButtonText:"
        @"snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");
    if (![cls respondsToSelector:sel]) { FBGRLogAppend(@"DogFood: nag selector missing"); return NO; }

    id session = FBGRActiveUserSession();
    if (!session) { FBGRLogAppend(@"DogFood: no FBUserSession"); return NO; }

    id onSwitch = [^(BOOL on){
        [FBGRPrefs() setBool:on forKey:kFBGRDogFoodMaster];
        [FBGRPrefs() synchronize];
        FBGRDogFoodApplyManagedFlag();
    } copy];
    id onSnooze = [^{ FBGRLogAppend(@"DogFood: snoozed"); } copy];

    UIViewController *vc = nil;
    @try {
        typedef id(*NagIMP)(id,SEL,id,id,id,id,id,BOOL,id,id);
        NagIMP imp = (NagIMP)[cls methodForSelector:sel];
        vc = imp(cls, sel, session,
                 @"FBTweaks DogFood",
                 @"Abrir o fluxo nativo de DogFood / Gold managed app?",
                 @"Ativar", @"Mais tarde", YES, onSwitch, onSnooze);
    } @catch (NSException *e) {
        FBGRLogAppend([NSString stringWithFormat:@"DogFood: nag exception %@", e.reason]);
        return NO;
    }
    if (!vc) return NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = FBGRTopVC();
        if (top) [top presentViewController:vc animated:YES completion:nil];
    });
    return YES;
}

// ── DLP Dogfooding Indicator — TARGETED hook (no global scan) ─────────────────
// _TtC24FBDLPDogfoodingIndicator32FBDLPDogfoodingIndicatorProvider
//   +componentWithLabel:session:  → returns a component shown when the DLP
//   dogfooding indicator is active. We don't fabricate one; we just ensure the
//   provider runs (it already self-gates on is_dlp_native_dogfooding... which
//   our MC hooks can force). This hook only LOGS so we can confirm it fires.
static IMP gOrigDLPComponent = NULL;
typedef id (*DLPCompIMP)(id, SEL, id, id);

static id h_DLPComponentWithLabelSession(id self, SEL _cmd, id label, id session) {
    if ([FBGRPrefs() boolForKey:kFBGRDLPIndicator])
        FBGRLogAppend(@"DLP: componentWithLabel:session: fired");
    return gOrigDLPComponent
        ? ((DLPCompIMP)gOrigDLPComponent)(self, _cmd, label, session)
        : nil;
}

static void FBGRInstallDLPHook(void) {
    Class cls = NSClassFromString(@"_TtC24FBDLPDogfoodingIndicator32FBDLPDogfoodingIndicatorProvider");
    if (!cls) { FBGRLogAppend(@"DLP: provider class not loaded yet"); return; }
    SEL sel = NSSelectorFromString(@"componentWithLabel:session:");
    if (gOrigDLPComponent || !class_getClassMethod(cls, sel)) return;
    // It's a class method → hook the metaclass.
    Class meta = object_getClass(cls);
    IMP orig = NULL;
    MSHookMessageEx(meta, sel, (IMP)h_DLPComponentWithLabelSession, &orig);
    if (orig) { gOrigDLPComponent = orig; FBGRLogAppend(@"DLP: hook installed"); }
}

// ── Public API ────────────────────────────────────────────────────────────────
extern "C" BOOL FBGRDogFoodIsEnabled(void) { return [FBGRPrefs() boolForKey:kFBGRDogFoodMaster]; }
extern "C" void FBGRDogFoodSetEnabled(BOOL on) {
    [FBGRPrefs() setBool:on forKey:kFBGRDogFoodMaster];
    [FBGRPrefs() synchronize];
    FBGRDogFoodApplyManagedFlag();
}

extern "C" NSString *FBGRDogFoodDiagnostic(void) {
    // Defensive: no global scan, only safe checks.
    Class ctrl = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    Class dlp  = NSClassFromString(@"_TtC24FBDLPDogfoodingIndicator32FBDLPDogfoodingIndicatorProvider");
    id session = FBGRActiveUserSession();
    BOOL managed = [[NSUserDefaults standardUserDefaults] boolForKey:@"FBDogFood-managedPhoneFlag"];
    return [NSString stringWithFormat:
        @"DogFoodController=%@\nDLPProvider=%@\nFBUserSession=%@\nmanagedPhoneFlag=%@\ndlpHook=%@\nmaster=%@",
        ctrl ? @"OK" : @"NOT FOUND",
        dlp  ? @"OK" : @"NOT FOUND",
        session ? @"OK" : @"nil",
        managed ? @"YES" : @"NO",
        gOrigDLPComponent ? @"installed" : @"no",
        FBGRDogFoodIsEnabled() ? @"ON" : @"OFF"];
}

// ── Constructor: delayed, targeted, NO global scan ────────────────────────────
__attribute__((constructor))
static void FBGRDogFoodCtor(void) {
    // Keep startup inert unless the user already enabled DogFood before.
    if (!FBGRDogFoodIsEnabled()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @autoreleasepool {
            FBGRDogFoodApplyManagedFlag();
            FBGRInstallDLPHook();
        }
    });
}
