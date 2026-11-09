// Facebook 567: native React DevMenu live-module resolver and read-only
// availability diagnostics for genuine internal controllers.
//
// Only uses exact class names + validated Objective-C ABI. No arbitrary method
// hook, all-class enumeration, or invocation of unknown plugin initializers.
#import "FBTNativeInternalSurfaces.h"
#import "../FBTUtils.h"
#import "../FBTDefaults.h"
#import "../FBTPrefix.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static BOOL FBTNSIsObjectGetter(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char *returnType = method_copyReturnType(method);
    BOOL valid = returnType && returnType[0] == '@';
    if (returnType) free(returnType);
    return valid;
}

static id FBTNSGet(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!FBTNSIsObjectGetter(object, selector)) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id FBTNSModuleFromBridge(id object, Class menuClass) {
    if (!object || !menuClass) return nil;
    NSString *name = NSStringFromClass([object class]);
    if (![name containsString:@"RCTBridge"] && ![name containsString:@"ReactBridge"]) return nil;
    SEL selector = NSSelectorFromString(@"moduleForClass:");
    if (![object respondsToSelector:selector]) return nil;
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != 3) return nil;
    char *ret = method_copyReturnType(method);
    char *arg = method_copyArgumentType(method, 2);
    BOOL valid = ret && ret[0] == '@' && arg && arg[0] == '#';
    if (ret) free(ret);
    if (arg) free(arg);
    if (!valid) return nil;
    @try {
        id module = ((id (*)(id, SEL, Class))objc_msgSend)(object, selector, menuClass);
        return [module isKindOfClass:menuClass] ? module : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void FBTNSQueueObject(NSMutableArray *queue, NSHashTable *seen, id object, NSUInteger depth) {
    if (!object || depth > 5 || queue.count >= 96 || [seen containsObject:object]) return;
    [seen addObject:object];
    [queue addObject:@{ @"object": object, @"depth": @(depth) }];
}

static id FBTNSFindLiveDevMenu(UIViewController *presenter, Class menuClass) {
    if (!menuClass || !presenter) return nil;
    NSMutableArray *queue = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    FBTNSQueueObject(queue, seen, presenter, 0);
    FBTNSQueueObject(queue, seen, presenter.navigationController, 0);
    FBTNSQueueObject(queue, seen, presenter.presentingViewController, 0);
    FBTNSQueueObject(queue, seen, [FBTUtils storedSession], 0);
    FBTNSQueueObject(queue, seen, [FBTUtils activeKeyWindow].rootViewController, 0);

    // Known React Native relationship getters; validated as object-returning
    // and zero-argument before every call.
    NSArray<NSString *> *getters = @[
        @"bridge", @"reactBridge", @"reactNativeBridge", @"currentBridge",
        @"devSettings", @"devMenu", @"rootView", @"reactRootView",
        @"contentView", @"view", @"session", @"userSession"
    ];
    for (NSUInteger index = 0; index < queue.count && index < 96; ++index) {
        NSDictionary *entry = queue[index];
        id obj = entry[@"object"];
        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        if ([obj isKindOfClass:menuClass]) return obj;
        id fromBridge = FBTNSModuleFromBridge(obj, menuClass);
        if (fromBridge) return fromBridge;
        if (depth >= 5) continue;

        for (NSString *name in getters) {
            id value = FBTNSGet(obj, name);
            if (value == obj || !value) continue;
            if ([value isKindOfClass:menuClass]) return value;
            // Restrict exploration to Objective-C objects, excluding collections,
            // strings and scalar value wrappers.
            if ([value isKindOfClass:[UIView class]] ||
                [value isKindOfClass:[UIViewController class]] ||
                [NSStringFromClass([value class]) containsString:@"RCT"] ||
                [NSStringFromClass([value class]) containsString:@"React"]) {
                FBTNSQueueObject(queue, seen, value, depth + 1);
            }
        }
        if ([obj isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = obj;
            FBTNSQueueObject(queue, seen, vc.presentedViewController, depth + 1);
            FBTNSQueueObject(queue, seen, vc.parentViewController, depth + 1);
            FBTNSQueueObject(queue, seen, vc.navigationController, depth + 1);
            FBTNSQueueObject(queue, seen, vc.tabBarController, depth + 1);
            for (UIViewController *child in vc.childViewControllers) {
                FBTNSQueueObject(queue, seen, child, depth + 1);
            }
        }
    }
    return nil;
}

BOOL FBTNativeShowReactDevMenu(UIViewController *presenter, NSString **error) {
    if (![NSThread isMainThread]) {
        if (error) *error = @"React Dev Menu precisa ser aberto na main thread.";
        return NO;
    }
    Class menuClass = NSClassFromString(@"RCTDevMenu");
    if (!menuClass) {
        if (error) *error = @"RCTDevMenu ainda não está registrado; abra uma tela React Native e tente novamente.";
        return NO;
    }
    id menu = FBTNSFindLiveDevMenu(presenter, menuClass);
    if (!menu) {
        if (error) *error = @"Não foi possível localizar a instância RCTDevMenu da bridge ativa. Nenhum módulo novo foi criado.";
        return NO;
    }
    SEL show = @selector(show);
    Method method = class_getInstanceMethod([menu class], show);
    if (!method || ![menu respondsToSelector:show] ||
        method_getNumberOfArguments(method) != 2) {
        if (error) *error = @"RCTDevMenu não expõe -show com a ABI esperada.";
        return NO;
    }
    char *returnType = method_copyReturnType(method);
    BOOL compatible = returnType && returnType[0] == 'v';
    if (returnType) free(returnType);
    if (!compatible) {
        if (error) *error = @"Assinatura -show divergente; chamada nativa não realizada.";
        return NO;
    }
    @try {
        ((void (*)(id, SEL))objc_msgSend)(menu, show);
        FBTLog(@"RCTDevMenu: called -show on active module %@", NSStringFromClass([menu class]));
        return YES;
    } @catch (NSException *exception) {
        if (error) *error = [NSString stringWithFormat:@"Falha ao abrir RCTDevMenu: %@", exception.reason ?: exception.name];
        return NO;
    }
}

NSString *FBTNativeInternalSurfacesReport(void) {
    NSArray<NSArray<NSString *> *> *items = @[
        @[@"DogFood/Gold", @"_TtC11FBDogFoodUI17DogFoodController"],
        @[@"RN Developer Menu", @"RCTDevMenu"],
        @[@"RN Developer Settings", @"RCTDevSettings"],
        @[@"RN Internal Settings", @"FBReactNativeInternalSettingsMenuItemHandler"],
        @[@"Dogfooding Assistant/RageShake", @"FBClientRageShakeBugReporterViewController"],
        @[@"FFDB Internal Settings", @"FFDBInternalSettingsViewController"],
        @[@"FFDB Internal Web", @"FFDBInternalSettingsWebViewController"],
        @[@"MobileConfig Debug", @"FBMobileConfigDebugViewController"],
        @[@"Internal Settings", @"FBInternalSettingsViewController"],
        @[@"Whitehat", @"FBWhitehatSettingsViewController"]
    ];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSArray<NSString *> *item in items) {
        Class cls = NSClassFromString(item[1]);
        [lines addObject:[NSString stringWithFormat:@"%@: %@%@",
            item[0], cls ? @"class registered" : @"class not loaded",
            cls ? [NSString stringWithFormat:@" (%@)", NSStringFromClass(cls)] : @""]];
    }
    [lines addObject:@"\nPresença da classe não comprova factory inicializado, provider ou elegibilidade."];
    [lines addObject:[NSString stringWithFormat:@"Employee toggle: %@",
        [FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ? @"ON" : @"OFF"]];
    [lines addObject:[NSString stringWithFormat:@"Dogfood local managedPhoneFlag: %@",
        [[NSUserDefaults standardUserDefaults] boolForKey:@"FBDogFood-managedPhoneFlag"] ? @"ON" : @"OFF"]];
    return [lines componentsJoinedByString:@"\n"];
}
