// Native Facebook DogFood/Gold sheet (Facebook iOS 567, ARM64).
// Factory: FBDogFoodUI.DogFoodController
// +getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:
//                       snoozeEnabled:onSwitch:onSnooze:
// Verified ObjC signature (Facebook 567): @76@0:8@16@24@32@40@48B56@?60@?68
// We supply the callbacks: the factory only creates the UI. It does not enroll
// devices into MDM/Gold or grant any Employee privileges on the server.

#import "FBTDogFoodNative.h"
#import "../FBTUtils.h"
#import "../FBTPrefix.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <stdlib.h>

static NSString *const kFBTManagedPhone = @"FBDogFood-managedPhoneFlag";
static NSString *const kFBTSnoozedOnDismiss = @"FBDogFood-lastSnoozedOnDismissDate";
static NSString *const kFBTSnoozedOnSwitch = @"FBDogFood-lastSnoozedOnSwitchDate";
static NSString *const kFBTDismissCount = @"FBDogFood-dismissClickCount";

BOOL FBTDogFoodManagedPhoneFlag(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kFBTManagedPhone];
}

void FBTDogFoodSetManagedPhoneFlag(BOOL enabled) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kFBTManagedPhone];
    if (enabled) {
        [defaults removeObjectForKey:kFBTSnoozedOnDismiss];
        [defaults removeObjectForKey:kFBTSnoozedOnSwitch];
        [defaults setInteger:0 forKey:kFBTDismissCount];
    }
    // Explicit readback and notification to observers in this process.
    BOOL actual = [defaults boolForKey:kFBTManagedPhone];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
    FBTLog(@"Dogfood managedPhoneFlag requested=%d readback=%d (local only)", enabled, actual);
}


static BOOL FBTDogFoodIsUserSession(id candidate, Class sessionClass) {
    if (!candidate) return NO;
    if (sessionClass && [candidate isKindOfClass:sessionClass]) return YES;
    // The native Swift bridge can expose concrete FBUserSession subclasses.
    NSString *name = NSStringFromClass([candidate class]);
    return [name isEqualToString:@"FBUserSession"] ||
           [name hasPrefix:@"FBUserSession_"];
}

static BOOL FBTDogFoodReturnIsObject(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char *encoding = method_copyReturnType(method);
    BOOL objectReturn = encoding && encoding[0] == '@';
    if (encoding) free(encoding);
    return objectReturn;
}

static id FBTDogFoodSafeGetter(id obj, NSString *name) {
    if (!obj || !name) return nil;
    SEL sel = NSSelectorFromString(name);
    if (![obj respondsToSelector:sel]) return nil;
    Method method = class_getInstanceMethod([obj class], sel);
    if (!FBTDogFoodReturnIsObject(method)) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(obj, sel); }
    @catch (__unused NSException *exception) { return nil; }
}

static id FBTDogFoodSafeClassGetter(Class cls, NSString *name) {
    if (!cls || !name) return nil;
    SEL sel = NSSelectorFromString(name);
    if (![cls respondsToSelector:sel]) return nil;
    Method method = class_getClassMethod(cls, sel);
    if (!FBTDogFoodReturnIsObject(method)) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(cls, sel); }
    @catch (__unused NSException *exception) { return nil; }
}

static id FBTDogFoodSafeIvar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar ivar = class_getInstanceVariable([obj class], name);
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') return nil;
    @try { return object_getIvar(obj, ivar); }
    @catch (__unused NSException *exception) { return nil; }
}

static void FBTDogFoodQueue(NSMutableArray *queue, NSHashTable *seen,
                            id object, NSUInteger depth) {
    if (!object || depth > 5 || queue.count >= 64 || [seen containsObject:object]) return;
    [seen addObject:object];
    [queue addObject:@{@"object": object, @"depth": @(depth)}];
}

// Prefer the session FBTabBarViewController already supplied to FBTUtils.
// When it wraps FBUserSession, use only known object getters/ivars, not a
// process-wide class sweep or unverified pointer casts.
static id FBTDogFoodResolveSession(UIViewController *presenter) {
    Class cls = NSClassFromString(@"FBUserSession");
    id captured = [FBTUtils storedSession];
    if (FBTDogFoodIsUserSession(captured, cls)) return captured;

    for (NSString *selector in @[@"activeSession", @"activeUserSession",
                                 @"currentSession", @"currentUserSession",
                                 @"sharedSession", @"defaultSession"]) {
        id candidate = FBTDogFoodSafeClassGetter(cls, selector);
        if (FBTDogFoodIsUserSession(candidate, cls)) return candidate;
    }

    NSMutableArray *queue = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    FBTDogFoodQueue(queue, seen, captured, 0);
    FBTDogFoodQueue(queue, seen, presenter, 0);
    FBTDogFoodQueue(queue, seen, presenter.presentingViewController, 0);
    UIWindow *window = [FBTUtils activeKeyWindow];
    FBTDogFoodQueue(queue, seen, window.rootViewController, 0);

    static NSArray<NSString *> *getters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        getters = @[@"userSession", @"fbUserSession", @"session", @"currentSession",
                    @"currentUserSession", @"activeSession", @"loggedInUserSession",
                    @"userSessionIfAvailable", @"sessionIfAlreadyExists"];
    });
    for (NSUInteger index = 0; index < queue.count && index < 64; ++index) {
        NSDictionary *entry = queue[index];
        id object = entry[@"object"];
        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        if (FBTDogFoodIsUserSession(object, cls)) return object;
        if (depth >= 5) continue;

        for (NSString *name in getters) {
            id next = FBTDogFoodSafeGetter(object, name);
            if (FBTDogFoodIsUserSession(next, cls)) return next;
            FBTDogFoodQueue(queue, seen, next, depth + 1);
        }
        for (NSString *name in @[@"_userSession", @"_fbUserSession", @"_session"]) {
            id next = FBTDogFoodSafeIvar(object, name.UTF8String);
            if (FBTDogFoodIsUserSession(next, cls)) return next;
            FBTDogFoodQueue(queue, seen, next, depth + 1);
        }
        if ([object isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)object;
            FBTDogFoodQueue(queue, seen, vc.parentViewController, depth + 1);
            FBTDogFoodQueue(queue, seen, vc.presentingViewController, depth + 1);
            FBTDogFoodQueue(queue, seen, vc.presentedViewController, depth + 1);
            FBTDogFoodQueue(queue, seen, vc.navigationController, depth + 1);
            FBTDogFoodQueue(queue, seen, vc.tabBarController, depth + 1);
            for (UIViewController *child in vc.childViewControllers) {
                FBTDogFoodQueue(queue, seen, child, depth + 1);
            }
        }
    }
    return nil;
}

static Class FBTDogFoodControllerClass(void) {
    Class cls = NSClassFromString(@"_TtC11FBDogFoodUI17DogFoodController");
    if (!cls) cls = NSClassFromString(@"FBDogFoodUI.DogFoodController");
    return cls;
}

static BOOL FBTDogFoodFactoryIsCompatible(Class cls, SEL selector) {
    if (!cls || ![cls respondsToSelector:selector]) return NO;
    Method method = class_getClassMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 10) return NO;
    char *ret = method_copyReturnType(method);
    char *booleanArg = method_copyArgumentType(method, 7);
    char *switchBlock = method_copyArgumentType(method, 8);
    char *snoozeBlock = method_copyArgumentType(method, 9);
    BOOL valid = ret && ret[0] == '@' && booleanArg &&
        (booleanArg[0] == 'B' || booleanArg[0] == 'c') &&
        switchBlock && !strncmp(switchBlock, "@?", 2) &&
        snoozeBlock && !strncmp(snoozeBlock, "@?", 2);
    if (ret) free(ret);
    if (booleanArg) free(booleanArg);
    if (switchBlock) free(switchBlock);
    if (snoozeBlock) free(snoozeBlock);
    return valid;
}

BOOL FBTDogFoodPresentNativeNag(UIViewController *presenter, NSString **error) {
    if (![NSThread isMainThread]) {
        if (error) *error = @"A tela DogFood deve ser aberta na main thread.";
        return NO;
    }
    if (!presenter || presenter.isBeingDismissed || presenter.presentedViewController) {
        if (error) *error = @"Aguarda o encerramento da tela modal atual.";
        return NO;
    }
    Class controller = FBTDogFoodControllerClass();
    SEL selector = NSSelectorFromString(
        @"getNagSheetWithSession:title:message:switchButtonText:"
         @"snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:");
    if (!FBTDogFoodFactoryIsCompatible(controller, selector)) {
        if (error) *error = @"DogFoodController ou assinatura nativa indisponível nesta build.";
        return NO;
    }
    id session = FBTDogFoodResolveSession(presenter);
    if (!session) {
        if (error) *error = @"FBUserSession ativa não encontrada. Abra o Facebook logado e volte a tentar.";
        return NO;
    }

    void (^onSwitch)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // Caller-provided callback, not the native Gold/MDM enrollment.
            // Keep this identical to the dedicated Dogfood settings switch.
            FBTDogFoodSetManagedPhoneFlag(YES);
        });
    };
    void (^onSnooze)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:[NSDate date] forKey:kFBTSnoozedOnDismiss];
            FBTLog(@"DogFood native snooze recorded locally");
        });
    };

    typedef id (*NagFactory)(id, SEL, id, id, id, id, id, BOOL, id, id);
    UIViewController *sheet = nil;
    @try {
        id result = ((NagFactory)objc_msgSend)(
            controller, selector, session,
            @"Facebook DogFood",
            @"Demonstração do aviso nativo. Ativar configura somente o indicador Dogfood local; não instala o Facebook Gold nem inscreve o aparelho no MDM.",
            @"Ativar localmente", @"Depois", YES, [onSwitch copy], [onSnooze copy]);
        if ([result isKindOfClass:[UIViewController class]]) sheet = (UIViewController *)result;
    } @catch (NSException *exception) {
        if (error) *error = [NSString stringWithFormat:
            @"Falha no factory nativo: %@", exception.reason ?: exception.name];
        return NO;
    }
    if (!sheet) {
        if (error) *error = @"O factory nativo retornou nil ou outro tipo de objeto.";
        return NO;
    }
    @try {
        [presenter presentViewController:sheet animated:YES completion:nil];
        FBTLog(@"DogFood: native sheet presented; session=%@",
               NSStringFromClass([session class]));
        return YES;
    } @catch (NSException *exception) {
        if (error) *error = [NSString stringWithFormat:
            @"Não foi possível apresentar o nag sheet: %@", exception.reason ?: exception.name];
        return NO;
    }
}
