// Facebook 567 native internal controllers. All classes/initializers below
// were checked against Objective-C metadata in the extracted IPA:
// FBRarelyUsedFramework (FFDB, About, OTA, download, push, media),
// FBSharedFramework (Clash Management, Employee option, Bug Reporter).
// Exact runtime ABI + valid session required; no fabricated context providers.

#import "FBTNativeInternalMenus.h"
#import "../FBTUtils.h"
#import "../FBTPrefix.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdlib.h>
#include <string.h>

static BOOL FBTNativeRequireClass(NSString *name, Class *outClass, NSString **failure) {
    Class cls = NSClassFromString(name);
    if (!cls) {
        NSString *bundlePath = [[[NSBundle mainBundle] privateFrameworksPath]
            stringByAppendingPathComponent:@"FBRarelyUsedFramework.framework"];
        NSError *loadingError = nil;
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        if (bundle && !bundle.isLoaded) [bundle loadAndReturnError:&loadingError];
        cls = NSClassFromString(name);
        if (!cls) {
            // The Messaging Thread View internal plugin lives in FBCameraFramework.
            NSString *cameraPath = [[[NSBundle mainBundle] privateFrameworksPath]
                stringByAppendingPathComponent:@"FBCameraFramework.framework"];
            NSBundle *camera = [NSBundle bundleWithPath:cameraPath];
            if (camera && !camera.isLoaded) [camera loadAndReturnError:nil];
            cls = NSClassFromString(name);
        }
        if (!cls && loadingError) {
            FBTLog(@"Native internal bundle load error: %@", loadingError.localizedDescription);
        }
    }
    if (!cls) {
        if (failure) *failure = [NSString stringWithFormat:
            @"Classe nativa %@ não registrada após carregar FBRarelyUsedFramework.", name];
        return NO;
    }
    if (outClass) *outClass = cls;
    return YES;
}

static BOOL FBTNativeCheckInitializer(Class cls, SEL selector, NSUInteger argc,
                                      BOOL sessionArgument) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != argc) return NO;
    char *ret = method_copyReturnType(method);
    BOOL valid = ret && ret[0] == '@';
    if (ret) free(ret);
    if (sessionArgument && valid) {
        char *arg = method_copyArgumentType(method, 2);
        valid = arg && arg[0] == '@';
        if (arg) free(arg);
    }
    return valid;
}

static BOOL FBTNativeCheckVoidNoArg(id obj, SEL selector) {
    Method method = obj ? class_getInstanceMethod([obj class], selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2 ||
        ![obj respondsToSelector:selector]) return NO;
    char *ret = method_copyReturnType(method);
    BOOL valid = ret && ret[0] == 'v';
    if (ret) free(ret);
    return valid;
}

static id FBTNativeGetter(id obj, NSString *selectorName) {
    if (!obj) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod([obj class], selector);
    if (![obj respondsToSelector:selector] || !method ||
        method_getNumberOfArguments(method) != 2) return nil;
    char *ret = method_copyReturnType(method);
    BOOL valid = ret && ret[0] == '@';
    if (ret) free(ret);
    if (!valid) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(obj, selector); }
    @catch (__unused NSException *e) { return nil; }
}

static id FBTNativeFindRelatedObject(Class target) {
    if (!target) return nil;
    NSMutableArray<NSDictionary *> *queue = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    NSMutableArray *seeds = [NSMutableArray array];
    if ([FBTUtils storedSession]) [seeds addObject:[FBTUtils storedSession]];
    UIViewController *top = [FBTUtils topMostController];
    if (top) [seeds addObject:top];
    UIViewController *root = [FBTUtils activeKeyWindow].rootViewController;
    if (root) [seeds addObject:root];
    for (id seed in seeds) {
        if (![seen containsObject:seed]) {
            [seen addObject:seed];
            [queue addObject:@{@"object":seed,@"depth":@0}];
        }
    }
    NSArray<NSString *> *names = @[
        @"bugReportInitialCoordinator", @"bugReportCoordinator",
        @"rageShakeCoordinator", @"rageshakeCoordinator",
        @"bugReporter", @"shakeHandler", @"coordinator",
        @"navigationCoordinator", @"fbNavigationCoordinator",
        @"navigationContext", @"selectedViewController", @"visibleViewController",
        @"topViewController", @"currentViewController", @"delegate", @"session",
        @"userSession", @"tabBarController"
    ];
    for (NSUInteger index = 0; index < queue.count && index < 96; ++index) {
        NSDictionary *entry = queue[index];
        id obj = entry[@"object"];
        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        if ([obj isKindOfClass:target]) return obj;
        if (depth >= 5) continue;
        NSMutableArray *next = [NSMutableArray array];
        for (NSString *name in names) {
            id candidate = FBTNativeGetter(obj, name);
            if (candidate) [next addObject:candidate];
        }
        if ([obj isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = obj;
            for (id candidate in @[vc.parentViewController ?: [NSNull null],
                                    vc.presentingViewController ?: [NSNull null],
                                    vc.navigationController ?: [NSNull null],
                                    vc.tabBarController ?: [NSNull null]]) {
                if (candidate != [NSNull null]) [next addObject:candidate];
            }
            [next addObjectsFromArray:vc.childViewControllers];
        }
        for (id candidate in next) {
            if (!candidate || [seen containsObject:candidate] ||
                [candidate isKindOfClass:[NSString class]] ||
                [candidate isKindOfClass:[NSNumber class]] ||
                [candidate isKindOfClass:[NSArray class]] ||
                [candidate isKindOfClass:[NSDictionary class]]) continue;
            [seen addObject:candidate];
            if (queue.count < 96) {
                [queue addObject:@{@"object":candidate,@"depth":@(depth + 1)}];
            }
        }
    }
    return nil;
}

static BOOL FBTNativePresentController(UIViewController *vc, NSString **failure) {
    if (![NSThread isMainThread] || !vc) {
        if (failure) *failure = @"A apresentação exige um UIViewController na main thread.";
        return NO;
    }
    UIViewController *presenter = [FBTUtils topMostController];
    if (!presenter || presenter.presentedViewController ||
        presenter.isBeingDismissed) {
        if (failure) *failure = @"Não existe apresentador livre para mostrar o menu nativo.";
        return NO;
    }
    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                           target:nav
                           action:@selector(fbt_dismissInternalSettings)];
    @try {
        [presenter presentViewController:nav animated:YES completion:nil];
        return YES;
    } @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:
            @"Falha ao apresentar %@: %@", NSStringFromClass([vc class]),
            exception.reason ?: exception.name];
        return NO;
    }
}

BOOL FBTNativeOpenController(NSString *identifier, NSString **failure) {
    if (![NSThread isMainThread]) {
        if (failure) *failure = @"O menu deve ser aberto na main thread.";
        return NO;
    }
    NSDictionary<NSString *, NSArray<NSString *> *> *catalog = @{
        @"ffdb": @[@"FFDBInternalSettingsViewController", @"init"],
        @"about": @[@"FBAboutInternalSettingsViewController", @"initWithSession:"],
        @"react_ota": @[@"FBInternalSettingsReactOTAViewController", @"initWithSession:"],
        @"on_demand": @[@"FBInternalSettingsDownloadOnDemandViewController", @"initWithSession:"],
        @"loggedout_push": @[@"FBLoggedOutPushInternalSettingsViewController", @"initWithSession:"],
        @"reliable_media": @[@"FBReliableMediaInternalSettingsViewController", @"initWithSession:"],
        @"clash": @[@"FBClashManagementInternalSettingsTableViewController", @"initWithSession:"],
        @"lifecycle": @[@"FBLifecycleInternalSettingsViewController", @"init"],
        @"autofill_tokenization": @[@"_TtC42AutofillTokenizationInternalSettingsPlugin52FBAutofillTokenizationInternalSettingsViewController", @"initWithStyle:"],
        @"messaging_thread": @[@"_TtC43FBMessagingThreadViewInternalSettingsPlugin51FBMessagingThreadViewInternalSettingsViewController", @"initWithStyle:"]
    };
    NSArray<NSString *> *entry = catalog[identifier ?: @""];
    if (!entry) {
        if (failure) *failure = @"Identificador de menu nativo não suportado.";
        return NO;
    }
    Class cls = Nil;
    if (!FBTNativeRequireClass(entry[0], &cls, failure)) return NO;
    if (![cls isSubclassOfClass:[UIViewController class]]) {
        if (failure) *failure = @"A classe foi encontrada, mas não é um UIViewController.";
        return NO;
    }

    BOOL needsSession = [entry[1] isEqualToString:@"initWithSession:"];
    BOOL needsStyle = [entry[1] isEqualToString:@"initWithStyle:"];
    SEL initializer = NSSelectorFromString(entry[1]);
    if (needsStyle && ![cls isSubclassOfClass:[UITableViewController class]]) {
        if (failure) *failure = @"initWithStyle: é exclusivo de UITableViewController nativo.";
        return NO;
    }
    BOOL abiValid = FBTNativeCheckInitializer(cls, initializer,
                                                (needsSession || needsStyle) ? 3 : 2, needsSession);
    if (abiValid && needsStyle) {
        Method method = class_getInstanceMethod(cls, initializer);
        char *style = method_copyArgumentType(method, 2);
        abiValid = style && (style[0] == 'q' || style[0] == 'i');
        if (style) free(style);
    }
    if (!abiValid) {
        if (failure) *failure = [NSString stringWithFormat:
            @"ABI do inicializador %@.%@ divergente da IPA 567.", entry[0],entry[1]];
        return NO;
    }
    id session = nil;
    if (needsSession) {
        session = [FBTUtils storedSession];
        Class sessionClass = NSClassFromString(@"FBUserSession");
        if (!session || (sessionClass && ![session isKindOfClass:sessionClass])) {
            if (failure) *failure = @"FBUserSession ativa não encontrada.";
            return NO;
        }
    }
    UIViewController *vc = nil;
    @try {
        id allocated = [cls alloc];
        vc = needsSession
            ? ((id (*)(id, SEL, id))objc_msgSend)(allocated, initializer, session)
            : needsStyle
            ? ((id (*)(id, SEL, NSInteger))objc_msgSend)(allocated, initializer, UITableViewStyleInsetGrouped)
            : ((id (*)(id, SEL))objc_msgSend)(allocated, initializer);
    } @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:
            @"Inicializador nativo lançou %@: %@", exception.name, exception.reason];
        return NO;
    }
    if (![vc isKindOfClass:[UIViewController class]]) {
        if (failure) *failure = @"O inicializador retornou nil ou um tipo inesperado.";
        return NO;
    }
    FBTLog(@"Native internal controller %@ initialized from original class",entry[0]);
    return FBTNativePresentController(vc,failure);
}

BOOL FBTNativeOpenDogfoodingAssistant(NSString **failure) {
    if (![NSThread isMainThread]) {
        if (failure) *failure = @"RageShake deve ser aberto na main thread.";
        return NO;
    }
    Class cls = Nil;
    if (!FBTNativeRequireClass(@"FBBugReportInitialCoordinator", &cls, failure)) return NO;
    id coordinator = FBTNativeFindRelatedObject(cls);
    if (!coordinator) {
        if (failure) *failure = @"O FBBugReportInitialCoordinator nativo não está exposto na sessão/árvore de controladores. Abra o RageShake do Facebook para inicializar o fluxo original.";
        return NO;
    }
    if (!FBTNativeCheckVoidNoArg(coordinator,@selector(openBugReportForm))) {
        if (failure) *failure = @"openBugReportForm não tem a assinatura nativa esperada.";
        return NO;
    }
    @try {
        ((void (*)(id, SEL))objc_msgSend)(coordinator, @selector(openBugReportForm));
        FBTLog(@"Native bug report form invoked (Dogfooding Assistant triage remains native)");
        return YES;
    } @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:
            @"RageShake original lançou %@", exception.reason ?: exception.name];
        return NO;
    }
}

BOOL FBTNativeOpenEmployeeUserOption(NSString **failure) {
    if (![NSThread isMainThread]) {
        if (failure) *failure = @"Employee User Option exige main thread.";
        return NO;
    }
    Class cls = Nil;
    if (!FBTNativeRequireClass(@"FBEmployeeSettingsUserOption", &cls, failure)) return NO;
    SEL initializer = NSSelectorFromString(@"initWithSession:tabID:navigationCoordinator:");
    Method method = class_getInstanceMethod(cls,initializer);
    BOOL employeeABI = method && method_getNumberOfArguments(method) == 5;
    if (employeeABI) {
        char *returnType = method_copyReturnType(method);
        employeeABI = returnType && returnType[0] == '@';
        if (returnType) free(returnType);
        for (unsigned index = 2; index <= 4 && employeeABI; ++index) {
            char *argument = method_copyArgumentType(method, index);
            employeeABI = argument && argument[0] == '@';
            if (argument) free(argument);
        }
    }
    if (!employeeABI) {
        if (failure) *failure = @"Assinatura de Employee Settings diferente da IPA 567.";
        return NO;
    }
    id session = [FBTUtils storedSession];
    id root = [FBTUtils activeKeyWindow].rootViewController;
    id navigationCoordinator = nil;
    Class coordinatorClass = NSClassFromString(@"FBNavigationCoordinatorImpl");
    if (coordinatorClass) navigationCoordinator = FBTNativeFindRelatedObject(coordinatorClass);
    if (!navigationCoordinator) navigationCoordinator = FBTNativeGetter(root,@"navigationCoordinator");

    id tabID = nil;
    for (id candidate in @[root ?: [NSNull null],
                            [FBTUtils topMostController] ?: [NSNull null]]) {
        if (candidate == [NSNull null]) continue;
        tabID = FBTNativeGetter(candidate,@"selectedTabID") ?:
                FBTNativeGetter(candidate,@"tabID") ?:
                FBTNativeGetter(candidate,@"selectedBookmarkID");
        if (tabID) break;
    }
    // Do not call with invented navigation coordinates or an arbitrary tab ID.
    if (!session || !navigationCoordinator || !tabID) {
        if (failure) *failure = [NSString stringWithFormat:
            @"O menu Employee exige objetos nativos: session=%@, tabID=%@, navigationCoordinator=%@. Nenhum argumento será fabricado.",
            session ? @"ok":@"ausente",tabID ? @"ok":@"ausente",
            navigationCoordinator ? @"ok":@"ausente"];
        return NO;
    }
    id option = nil;
    @try {
        option = ((id (*)(id, SEL, id, id, id))objc_msgSend)(
            [cls alloc],initializer,session,tabID,navigationCoordinator);
    } @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:
            @"Employee Settings init lançou %@", exception.reason ?: exception.name];
        return NO;
    }
    if (!FBTNativeCheckVoidNoArg(option,@selector(performUserOptionAction))) {
        if (failure) *failure = @"Employee Settings não retornou uma opção nativa válida.";
        return NO;
    }
    @try {
        ((void (*)(id, SEL))objc_msgSend)(option, @selector(performUserOptionAction));
        return YES;
    } @catch (NSException *exception) {
        if (failure) *failure = [NSString stringWithFormat:
            @"Employee Settings action lançou %@", exception.reason ?: exception.name];
        return NO;
    }
}
