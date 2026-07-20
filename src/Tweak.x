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
// em group instalados condicionalmente. Hooks C (fishhook) são instalados
// por helpers chamados do ctor quando a flag latched está on.
// Nenhuma chamada ObjC em hot path; nada de dispatch_after p/ instalar hook.
// =====================================================================

// Helpers de instalação implementados nos arquivos de feature:
extern void FBTInstallLiquidGlassHooks(void);   // Features/LiquidGlass
extern void FBTInstallDogfoodObserver(void);     // Features/Dogfood (notif observer)
extern void FBTInitEmployeeGroup(void);
extern void FBTInstallKnownGateRuntimeHooks(void);
extern void FBTInitTestUserInternalConfigGroup(void);
extern void FBTInitFloatingTabBarGroup(void);
extern void FBTInitDatingGroup(void);

// ---------------------------------------------------------------------
// Host do long-press: FBTabBarViewController.
// Confirmado: viewDidAppear:, _handleLongPress:, session.
// ---------------------------------------------------------------------
%group FBTHost

%hook FBTabBarViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    // Guarda a sessão p/ o opener de internal settings nativo.
    @try {
        id session = [self session];
        if (session) [FBTUtils setStoredSession:session];
    } @catch (__unused NSException *e) {}

    // Retry barato para classes Swift/dynamic que podem aparecer depois do
    // constructor. O instalador é idempotente e não enumera todas as classes.
    if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ||
        [FBTDefaults boolForKey:FBTKeyTestUserEnabled] ||
        [FBTDefaults boolForKey:FBTKeyKnownDogfoodEnabled]) {
        FBTInstallKnownGateRuntimeHooks();
    }
    if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) {
        FBTInstallMobileConfigDebugUIHooks();
    }

    // Anexa o gesto uma única vez por instância.
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

%end // FBTHost

// ---------------------------------------------------------------------
// ctor
// ---------------------------------------------------------------------
%ctor {
    @autoreleasepool {
        [FBTDefaults registerDefaultsOnce];

        // Host do painel sempre instala (gate real é dentro do gesto/pref).
        %init(FBTHost);

        // Observer p/ "abrir internal settings nativo" (barato; sem hook).
        FBTInstallDogfoodObserver();

        // Hooks conhecidos. Cada group só é inicializado quando uma das
        // famílias correspondentes já estava ligada no launch.
        BOOL employeeOn = [FBTDefaults boolForKey:FBTKeyEmployeeEnabled];
        BOOL testUserOn = [FBTDefaults boolForKey:FBTKeyTestUserEnabled];
        BOOL dogfoodOn = [FBTDefaults boolForKey:FBTKeyKnownDogfoodEnabled];
        BOOL rnInternalOn = [FBTDefaults boolForKey:FBTKeyReactNativeInternalEnabled];
        BOOL betaBuildOn = [FBTDefaults boolForKey:FBTKeyBetaBuildEnabled];

        if (employeeOn || testUserOn || dogfoodOn) FBTInitEmployeeGroup();
        if (testUserOn) FBTInitTestUserInternalConfigGroup();
        if (employeeOn || testUserOn || rnInternalOn) FBTInitReactNativeInternalGroup();
        if (employeeOn || testUserOn || rnInternalOn || betaBuildOn) FBTInstallReactNativeAndBuildImportHooks();
        if ([FBTDefaults boolForKey:FBTKeyFloatingTabBarEnabled]) FBTInitFloatingTabBarGroup();
        if ([FBTDefaults boolForKey:FBTKeyDatingEnabled]) FBTInitDatingGroup();

        if (employeeOn || testUserOn ||
            [FBTDefaults boolForKey:FBTKeyInternalCImportsEnabled] ||
            [FBTDefaults boolForKey:FBTKeyEasyGatingInternalEnabled]) {
            FBTInstallInternalImportHooks();
        }

        if ([FBTDefaults boolForKey:FBTKeyEmployeeSweepEnabled]) {
            // disabled at launch: employee sweep is manual post-launch
        }
        if ([FBTDefaults boolForKey:FBTKeyDogfoodSweepEnabled]) {
            // disabled at launch: dogfood sweep is manual post-launch
        }
        if ([FBTDefaults boolForKey:FBTKeyInternalDebugSweepEnabled]) {
            // disabled at launch: internaldebug sweep is manual post-launch
        }

        if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) {
            FBTInstallMobileConfigDebugUIBootstrap();
        }

        // Runtime browsers. Não varrem classes no launch: só reinstalam hooks
        // persistidos e, no MobileConfig, fishhookam readers conhecidos se a
        // flag runtime já estava on.
        if ([FBTDefaults boolForKey:FBTKeyRuntimeBoolBrowserEnabled]) {
            FBTRuntimeBoolReinstallPersistedHooks();
            [FBTSymbolBrowserEngine reinstallPersistedHooks];
        }

        if ([FBTDefaults boolForKey:FBTKeyMobileConfigRuntimeEnabled]) {
            // disabled at launch: native MC context capture is manual post-launch
            // disabled at launch: MC runtime is manual post-launch
        }

        [[NSNotificationCenter defaultCenter]
            addObserverForName:FBTNotificationPrefsChanged
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        FBTMobileConfigReloadPrefs();
                        FBTRuntimeBoolReloadPrefs();
                        FBTInternalImportReloadPrefs();
                        if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ||
                            [FBTDefaults boolForKey:FBTKeyTestUserEnabled] ||
                            [FBTDefaults boolForKey:FBTKeyKnownDogfoodEnabled]) {
                            FBTInstallKnownGateRuntimeHooks();
                        }
                        if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) {
                            FBTInstallMobileConfigDebugUIHooks();
                        }
                    }];

        // Hook C (fishhook) — flag latched no ctor; precisa restart p/ alternar.
        if ([FBTDefaults boolForKey:FBTKeyLiquidGlassEnabled]) {
            FBTInstallLiquidGlassHooks();
        }

        FBTLog(@"ctor done (master=%d)", [[NSUserDefaults standardUserDefaults] boolForKey:FBTKeyMasterEnabled]);
    }
}
