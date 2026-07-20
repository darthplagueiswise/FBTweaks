#import "FBTPrefix.h"
#import "FacebookHeaders.h"
#import "FBTDefaults.h"
#import "FBTReactNativeInternal.h"
#include "../../../modules/fishhook/fishhook.h"

// FBReactNativeProductsFramework families mapped in the current build:
// - RCTCurrentViewer propagates employee state into RN.
// - RCTDevMenu/RCTDevSettings are the concrete RN internal/dev surfaces.
// - RCTDevLoadingViewGet/SetEnabled are imported C functions with verified
//   BOOL(void) / void(BOOL) ABI.
// - METAOSBuildIsBeta is imported by Facebook and has verified BOOL(void) ABI.
// There is no callable TestFlight-receipt predicate in this framework;
// deviceBuildType/buildFlavor are product telemetry, not global gates.

static inline BOOL FBTRNInternalOn(void) {
    return [FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ||
           [FBTDefaults boolForKey:FBTKeyTestUserEnabled] ||
           [FBTDefaults boolForKey:FBTKeyReactNativeInternalEnabled];
}

static inline BOOL FBTEmployeeOn(void) {
    return [FBTDefaults boolForKey:FBTKeyEmployeeEnabled];
}

%group FBTReactNativeInternal

%hook RCTCurrentViewer
- (void)setIsEmployee:(BOOL)value {
    %orig(FBTEmployeeOn() ? YES : value);
}
%end

%hook FBInspirationMediaCompositionViewController
- (BOOL)isEligibleForDebugIndicatorWithEmployeeCondition:(BOOL)condition {
    // Preserve all non-employee requirements calculated by the original.
    if (FBTEmployeeOn()) return %orig(YES);
    return %orig(condition);
}
%end

%hook RCTDevMenu
- (BOOL)devMenuEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setDevMenuEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
- (BOOL)shakeToShow {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setShakeToShow:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
- (BOOL)profilingEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setProfilingEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
- (BOOL)hotLoadingEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setHotLoadingEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
- (BOOL)hotkeysEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setHotkeysEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
- (BOOL)keyboardShortcutsEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setKeyboardShortcutsEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
%end

%hook RCTDevMenuItem
- (BOOL)isDisabled {
    return FBTRNInternalOn() ? NO : %orig;
}
- (void)setDisabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? NO : value);
}
%end

%hook RCTDevSettings
- (BOOL)isDeviceDebuggingAvailable {
    return FBTRNInternalOn() ? YES : %orig;
}
- (BOOL)isHotLoadingAvailable {
    return FBTRNInternalOn() ? YES : %orig;
}
- (BOOL)isShakeToShowDevMenuEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setIsShakeToShowDevMenuEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
- (BOOL)isShakeGestureEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setIsShakeGestureEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
- (BOOL)isProfilingEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setProfilingEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
- (BOOL)isHotLoadingEnabled {
    return FBTRNInternalOn() ? YES : %orig;
}
- (void)setHotLoadingEnabled:(BOOL)value {
    %orig(FBTRNInternalOn() ? YES : value);
}
%end

%end // FBTReactNativeInternal

typedef BOOL (*FBTBoolVoidCFunction)(void);
typedef void (*FBTVoidBoolCFunction)(BOOL);

static BOOL sRNInternalLatched = NO;
static BOOL sBetaBuildLatched = NO;
static BOOL sRNImportHooksInstalled = NO;
static BOOL sBetaImportHookInstalled = NO;
static BOOL sRNGroupInitialized = NO;
static BOOL sRNBundleObserverInstalled = NO;

static FBTBoolVoidCFunction orig_RCTDevLoadingViewGetEnabled = NULL;
static FBTVoidBoolCFunction orig_RCTDevLoadingViewSetEnabled = NULL;
static FBTBoolVoidCFunction orig_METAOSBuildIsBeta = NULL;

static BOOL fbt_RCTDevLoadingViewGetEnabled(void) {
    if (sRNInternalLatched) return YES;
    return orig_RCTDevLoadingViewGetEnabled ? orig_RCTDevLoadingViewGetEnabled() : NO;
}

static void fbt_RCTDevLoadingViewSetEnabled(BOOL value) {
    if (orig_RCTDevLoadingViewSetEnabled) {
        orig_RCTDevLoadingViewSetEnabled(sRNInternalLatched ? YES : value);
    }
}

static BOOL fbt_METAOSBuildIsBeta(void) {
    if (sBetaBuildLatched) return YES;
    return orig_METAOSBuildIsBeta ? orig_METAOSBuildIsBeta() : NO;
}

void FBTInitReactNativeInternalGroup(void) {
    if (sRNGroupInitialized) return;

    // Do not consume Logos initialization before the RN framework registered a
    // target class. Bundle and tab-host retries call this again after loading.
    if (!objc_getClass("RCTCurrentViewer") &&
        !objc_getClass("RCTDevMenu") &&
        !objc_getClass("RCTDevSettings")) {
        return;
    }

    %init(FBTReactNativeInternal);
    sRNGroupInitialized = YES;
    FBTLog(@"React Native employee/internal group installed");
}

static void FBTInstallRNBundleObserver(void) {
    if (sRNBundleObserverInstalled) return;
    sRNBundleObserverInstalled = YES;

    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSBundleDidLoadNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        NSBundle *bundle = [note.object isKindOfClass:[NSBundle class]] ? note.object : nil;
        NSString *last = bundle.bundlePath.lastPathComponent ?: @"";
        if ([last containsString:@"FBReactNativeProductsFramework"] ||
            [last containsString:@"FBSharedDynamicFramework"] ||
            [last containsString:@"FBRarelyUsedFramework"]) {
            FBTInitReactNativeInternalGroup();
        }
    }];
}

void FBTInstallReactNativeAndBuildImportHooks(void) {
    BOOL wantsRN = FBTRNInternalOn();
    BOOL wantsBeta = [FBTDefaults boolForKey:FBTKeyBetaBuildEnabled];

    if (wantsRN) {
        FBTInstallRNBundleObserver();
        FBTInitReactNativeInternalGroup();
    }

    // Imported C gates are latched when installed. Turning these families back
    // off requires a process restart; signed __TEXT pages are never patched.
    if (wantsRN && !sRNImportHooksInstalled) {
        sRNInternalLatched = YES;
        struct rebinding rnBindings[] = {
            {
                "RCTDevLoadingViewGetEnabled",
                (void *)fbt_RCTDevLoadingViewGetEnabled,
                (void **)&orig_RCTDevLoadingViewGetEnabled
            },
            {
                "RCTDevLoadingViewSetEnabled",
                (void *)fbt_RCTDevLoadingViewSetEnabled,
                (void **)&orig_RCTDevLoadingViewSetEnabled
            },
        };
        rebind_symbols(rnBindings, 2);
        sRNImportHooksInstalled = YES;
        FBTLog(@"RN dev-loading imports installed");
    }

    if (wantsBeta && !sBetaImportHookInstalled) {
        sBetaBuildLatched = YES;
        struct rebinding betaBinding = {
            "METAOSBuildIsBeta",
            (void *)fbt_METAOSBuildIsBeta,
            (void **)&orig_METAOSBuildIsBeta
        };
        rebind_symbols(&betaBinding, 1);
        sBetaImportHookInstalled = YES;
        FBTLog(@"METAOSBuildIsBeta import installed");
    }
}

void FBTOpenReactNativeInternalSettings(void) {
    NSURL *url = [NSURL URLWithString:@"fb://rninternalsettings"];
    if (!url) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication]
            openURL:url
            options:@{}
            completionHandler:^(BOOL success) {
                FBTLog(@"RN Internal Settings route opened=%d", success);
            }];
    });
}
