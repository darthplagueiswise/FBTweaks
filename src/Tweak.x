#import "FBTPrefix.h"
#import "FacebookHeaders.h"
#import "FBTDefaults.h"
#import "Runtime/FBTSymbolBrowserEngine.h"
#import "FBTUtils.h"
#import "Runtime/FBTMobileConfigRuntime.h"
#import "Runtime/FBTRuntimeBoolBrowser.h"
#import "Runtime/FBTNativeTrace.h"
#import "Runtime/FBTNativeMobileConfigOverrides.h"
#import "Runtime/FBTMobileConfigDebugUIHooks.h"
#import "Features/Employee/FBTInternalImports.h"
#import "Features/ReactNative/FBTReactNativeInternal.h"
#import "Settings/FBTEntryPoints.h"
#include <stdlib.h>

// =====================================================================
// FBTweak — entrypoint
//
// Filosofia (Ryukgram): ctor é só gate barato de pref. Hooks ObjC vivem
// em groups instalados condicionalmente. Hooks C (fishhook) são instalados
// por helpers chamados quando a família está ativa. Nenhum patch em __TEXT.
// =====================================================================

extern void FBTInstallLiquidGlassHooks(void);
extern void FBTInstallDogfoodObserver(void);
extern void FBTInitEmployeeGroup(void);
extern void FBTInstallKnownGateRuntimeHooks(void);
extern void FBTInitFloatingTabBarGroup(void);
extern void FBTInitDatingGroup(void);

// Process-local Mobile Lab gate. Does not hook native functions or patch __TEXT.
// The host can cache NSProcessInfo.environment / FBMobileLabIsActive; this
// preference is evaluated only during process startup.
static void FBTConfigureMobileLabEnvironment(void) {
    if (![FBTDefaults boolForKey:FBTKeyMobileLabEnabled]) return;
    (void)setenv("LAB_IS_ACTIVE", "1", 0); // never overwrite inherited state
}

// Do not restore user-selected runtime hooks in dyld initializers.
// Hook recovery is deferred until the host view is displayed.
static BOOL sFBTRuntimeBrowserReady = NO;

static void FBTInstallEnabledKnownFamilies(void) {
    BOOL employeeOn = [FBTDefaults boolForKey:FBTKeyEmployeeEnabled];
    BOOL testUserOn = [FBTDefaults boolForKey:FBTKeyTestUserEnabled];
    BOOL dogfoodOn = [FBTDefaults boolForKey:FBTKeyKnownDogfoodEnabled];
    BOOL rnInternalOn = [FBTDefaults boolForKey:FBTKeyReactNativeInternalEnabled];
    BOOL betaBuildOn = [FBTDefaults boolForKey:FBTKeyBetaBuildEnabled];

    if (employeeOn || testUserOn || dogfoodOn) {
        FBTInitEmployeeGroup();
        FBTInstallKnownGateRuntimeHooks();
    }

    if (employeeOn || testUserOn || rnInternalOn) {
        FBTInitReactNativeInternalGroup();
    }

    if (employeeOn || testUserOn || rnInternalOn || betaBuildOn) {
        FBTInstallReactNativeAndBuildImportHooks();
    }

    if (employeeOn || testUserOn ||
        [FBTDefaults boolForKey:FBTKeyInternalCImportsEnabled] ||
        [FBTDefaults boolForKey:FBTKeyEasyGatingInternalEnabled]) {
        FBTInstallInternalImportHooks();
    }

    if ([FBTDefaults boolForKey:FBTKeyMobileConfigRuntimeEnabled]) {
        FBTInstallMobileConfigRuntime();
    }
    if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) {
        FBTInstallMobileConfigDebugUIHooks();
    }
}

%group FBTHost

%hook FBTabBarViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    @try {
        id session = [self session];
        [FBTUtils setStoredSession:session];
    } @catch (__unused NSException *e) {}

    // Retry exato e idempotente para Swift/Dynamic/RN/RarelyUsed que podem ser
    // carregados depois do constructor. Não enumera classes globalmente.
    FBTInstallEnabledKnownFamilies();
    FBTNativeTraceReloadPrefs();
    // Delayed, exact-target restoration: post-launch only. Never install
    // arbitrary persisted selectors from the dyld constructor.
    static dispatch_once_t restoreOnce;
    dispatch_once(&restoreOnce, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if ([FBTDefaults boolForKey:FBTKeyRuntimeBoolBrowserEnabled]) {
                FBTRuntimeBoolReinstallPersistedHooks(); // single hook owner
            }
            sFBTRuntimeBrowserReady = YES;
        });
    });
    if (sFBTRuntimeBrowserReady) FBTRuntimeBoolRetryPendingHooks();

    FBTRetryEntryPoints();
}

- (void)setSession:(id)session {
    %orig;
    [FBTUtils setStoredSession:session];
}

%end
%end

%ctor {
    @autoreleasepool {
        [FBTDefaults registerDefaultsOnce];
        FBTConfigureMobileLabEnvironment(); // before FBTweak hooks
        // Ring buffer initialized on demand after the host UI appears.
        // Migrate away from the duplicate employee sweep before loading hooks.
        // Only sweep:employee entries are removed; manual overrides remain.
        FBTRuntimeBoolClearSweep(@"employee");
        if ([[NSUserDefaults standardUserDefaults] boolForKey:FBTKeyEmployeeSweepEnabled]) {
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:FBTKeyEmployeeSweepEnabled];
        }

        %init(FBTHost);
        FBTInstallEntryPoints();
        FBTInstallDogfoodObserver();

        FBTInstallEnabledKnownFamilies();

        if ([FBTDefaults boolForKey:FBTKeyFloatingTabBarEnabled]) {
            FBTInitFloatingTabBarGroup();
        }
        if ([FBTDefaults boolForKey:FBTKeyDatingEnabled]) {
            FBTInitDatingGroup();
        }

        // No arbitrary persisted selector hooks from %ctor: a stale target or
        // colliding hook can otherwise make the IPA abort before first frame.
        // The host view restores only eligible post-launch targets.

        // O bootstrap só registra um observer filtrado e tenta classes exatas.
        if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled] ||
            [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
            FBTInstallMobileConfigDebugUIBootstrap();
        }

        [[NSNotificationCenter defaultCenter]
            addObserverForName:FBTNotificationPrefsChanged
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        if (![FBTDefaults boolForKey:FBTKeyMasterEnabled]) FBTMobileConfigSetSessionActive(NO);
                        FBTMobileConfigReloadPrefs();
                        FBTRuntimeBoolReloadPrefs();
                        FBTNativeTraceReloadPrefs();
                        FBTInternalImportReloadPrefs();
                        FBTInstallEnabledKnownFamilies();

                        if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled] ||
                            [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
                            FBTInstallMobileConfigDebugUIBootstrap();
                        }
                    }];

        // Liquid Glass C import remains launch-latched.
        if ([FBTDefaults boolForKey:FBTKeyLiquidGlassEnabled]) {
            FBTInstallLiquidGlassHooks();
        }

        FBTLog(@"ctor done (master=%d)",
               [[NSUserDefaults standardUserDefaults] boolForKey:FBTKeyMasterEnabled]);
    }
}
