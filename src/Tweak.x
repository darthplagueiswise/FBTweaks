#import "FBTPrefix.h"
#import "FacebookHeaders.h"
#import "FBTDefaults.h"
#import "FBTUtils.h"
#import "Runtime/FBTMobileConfigRuntime.h"
#import "Runtime/FBTRuntimeBoolBrowser.h"
#import "Runtime/FBTNativeMobileConfigOverrides.h"

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

        // Hooks ObjC condicionais (cada grupo lê sua pref):
        if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled])       FBTInitEmployeeGroup();
        if ([FBTDefaults boolForKey:FBTKeyFloatingTabBarEnabled]) FBTInitFloatingTabBarGroup();
        if ([FBTDefaults boolForKey:FBTKeyDatingEnabled])         FBTInitDatingGroup();

        // Runtime browsers. Não varrem classes no launch: só reinstalam hooks
        // persistidos e, no MobileConfig, fishhookam readers conhecidos se a
        // flag runtime já estava on.
        if ([FBTDefaults boolForKey:FBTKeyRuntimeBoolBrowserEnabled]) {
            FBTRuntimeBoolReinstallPersistedHooks();
        }

        if ([FBTDefaults boolForKey:FBTKeyMobileConfigRuntimeEnabled]) {
            FBTInstallNativeMobileConfigContextCapture();
            FBTInstallMobileConfigRuntime();
        }

        [[NSNotificationCenter defaultCenter]
            addObserverForName:FBTNotificationPrefsChanged
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        FBTMobileConfigReloadPrefs();
                        FBTRuntimeBoolReloadPrefs();
                    }];

        // Hook C (fishhook) — flag latched no ctor; precisa restart p/ alternar.
        if ([FBTDefaults boolForKey:FBTKeyLiquidGlassEnabled]) {
            FBTInstallLiquidGlassHooks();
        }

        FBTLog(@"ctor done (master=%d)", [[NSUserDefaults standardUserDefaults] boolForKey:FBTKeyMasterEnabled]);
    }
}
