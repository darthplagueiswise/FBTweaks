#import "FBTPrefix.h"
#import "FacebookHeaders.h"
#import "FBTDefaults.h"
#import "Runtime/FBTSymbolBrowserEngine.h"
#import "FBTUtils.h"
#import "Runtime/FBTMobileConfigRuntime.h"
#import "Runtime/FBTRuntimeBoolBrowser.h"
#import "Runtime/FBTNativeMobileConfigOverrides.h"
#import "Runtime/FBTMobileConfigDebugUIHooks.h"
#import "Features/Employee/FBTInternalImports.h"
#import "Features/ReactNative/FBTReactNativeInternal.h"

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
        if (session) [FBTUtils setStoredSession:session];
    } @catch (__unused NSException *e) {}

    // Retry exato e idempotente para Swift/Dynamic/RN/RarelyUsed que podem ser
    // carregados depois do constructor. Não enumera classes globalmente.
    FBTInstallEnabledKnownFamilies();

    static char kFBTGestureAttachedKey;
    if (objc_getAssociatedObject(self, &kFBTGestureAttachedKey)) return;
    objc_setAssociatedObject(self, &kFBTGestureAttachedKey, @(YES),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(fbt_handleLongPress:)];
    lp.minimumPressDuration = 0.6;
    [self.view addGestureRecognizer:lp];
}

%new
- (void)fbt_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    if (![FBTDefaults boolForKey:FBTKeyOpenLongPress]) return;

    id session = nil;
    @try { session = [self session]; } @catch (__unused NSException *e) {}
    [FBTUtils presentSettingsFromView:sender.view session:session];
}

%end
%end

%ctor {
    @autoreleasepool {
        [FBTDefaults registerDefaultsOnce];

        %init(FBTHost);
        FBTInstallDogfoodObserver();

        FBTInstallEnabledKnownFamilies();

        if ([FBTDefaults boolForKey:FBTKeyFloatingTabBarEnabled]) {
            FBTInitFloatingTabBarGroup();
        }
        if ([FBTDefaults boolForKey:FBTKeyDatingEnabled]) {
            FBTInitDatingGroup();
        }

        // Sweeps globais nunca executam no launch. Só reinstalamos alvos exatos
        // já persistidos, sem class scan/dladdr em initializers do dyld.
        if ([FBTDefaults boolForKey:FBTKeyRuntimeBoolBrowserEnabled]) {
            FBTRuntimeBoolReinstallPersistedHooks();
            [FBTSymbolBrowserEngine reinstallPersistedHooks];
        }

        // O bootstrap só registra um observer filtrado e tenta classes exatas.
        if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) {
            FBTInstallMobileConfigDebugUIBootstrap();
        }

        [[NSNotificationCenter defaultCenter]
            addObserverForName:FBTNotificationPrefsChanged
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        FBTMobileConfigReloadPrefs();
                        FBTRuntimeBoolReloadPrefs();
                        FBTInternalImportReloadPrefs();
                        FBTInstallEnabledKnownFamilies();

                        if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) {
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
