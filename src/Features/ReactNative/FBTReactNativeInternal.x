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
// - METAOSBuildIsBeta is imported by Facebook and has BOOL(void) ABI.
// There is no callable TestFlight predicate in this framework; buildFlavor and
// deviceBuildType entries here are telemetry, not gates.

static inline BOOL FBTRNInternalOn(void) {
    return [FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ||
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
    if (FBTEmployeeOn()) return YES;
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
%end

%end // FBTReactNativeInternal

typedef BOOL (*FBTBoolVoidCFunction)(void);
typedef void (*FBTVoidBoolCFunction)(BOOL);

static BOOL sRNInternalLatched = NO;
static BOOL sBetaBuildLatched = NO;
static BOOL sRNImportHooksInstalled = NO;
static BOOL sBetaImportHookInstalled = NO;

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

void FBTInstallReactNativeAndBuildImportHooks(void) {
    BOOL wantsRN = FBTRNInternalOn();
    BOOL wantsBeta = [FBTDefaults boolForKey:FBTKeyBetaBuildEnabled];

    // C-import gates are latched when installed and therefore require restart
    // to turn back off. RN and beta are installed independently so enabling one
    // family first does not prevent the other from being added later.
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

void FBTInitReactNativeInternalGroup(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init(FBTReactNativeInternal);
    });
}
