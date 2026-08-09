#import "FBTMessengerFlags.h"
#import "../../FBTDefaults.h"
#import "../../UI/FBTMessengerQuickMenu.h"
#include "../../../modules/fishhook/fishhook.h"
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// -------------------------------------------------------------------------
// Messenger 574.0.0 (1035554267) — validated MobileConfig descriptors.
//
// These are packed descriptor keys, not offsets and not __TEXT patches.
// LightSpeedCore imports MSGCSessionedMobileConfigGetBoolean from
// LightSpeedEngine, so fishhook updates the import slot without modifying a
// signed executable page.
// -------------------------------------------------------------------------

static const uint64_t kMCFBFordCanAccessInternalSettings = UINT64_C(0x008103fe00051470);
static const uint64_t kMCFBFordIsEmployee = UINT64_C(0x008103fe000b1472);
static const uint64_t kMCSecretConversationIsEmployee = UINT64_C(0x008104aa0006174b);

static const uint64_t kMCLabyrinthDevDebugUX = UINT64_C(0x00810130001606e3);
static const uint64_t kMCLabyrinthEBDebugMenu = UINT64_C(0x00810130007c071b);
static const uint64_t kMCLabyrinthEBDebugAdvancedMenu = UINT64_C(0x00810130007d071c);
static const uint64_t kMCLabyrinthEBDebugUserOverrides = UINT64_C(0x008101300140078a);

static const uint64_t kMCHomebaseMailboxSync = UINT64_C(0x0081065800001c1b);
static const uint64_t kMCHomebaseTab = UINT64_C(0x0081065800011c1c);
static const uint64_t kMCHomebaseCalendarRSVP = UINT64_C(0x0081065800051c1d);
static const uint64_t kMCHomebaseListAddRow = UINT64_C(0x2081065800101c1e);
static const uint64_t kMCHomebaseThreadSettings = UINT64_C(0x0081065800131c1f);

static atomic_bool sEmployeeEnabled;
static atomic_bool sInternalSettingsEnabled;
static atomic_bool sInternalToolsEnabled;
static atomic_bool sHomebaseEnabled;
static atomic_bool sHooksScheduled;

static BOOL FBTMessengerEmployeeEnabled(void) {
    return atomic_load_explicit(&sEmployeeEnabled, memory_order_relaxed);
}

static BOOL FBTMessengerInternalToolsEnabled(void) {
    return atomic_load_explicit(&sInternalToolsEnabled, memory_order_relaxed);
}

static void FBTMessengerReloadPreferences(void) {
    BOOL internalTools = [FBTDefaults boolForKey:FBTKeyMessengerInternalToolsEnabled];
    BOOL internalSettings = internalTools ||
        [FBTDefaults boolForKey:FBTKeyMessengerInternalSettingsEnabled];
    BOOL employee = internalSettings ||
        [FBTDefaults boolForKey:FBTKeyEmployeeEnabled];
    BOOL homebase = [FBTDefaults boolForKey:FBTKeyMessengerHomebaseEnabled] ||
        [FBTDefaults boolForKey:FBTKeyMessengerHouseholdEnabled];

    atomic_store_explicit(&sInternalToolsEnabled, internalTools, memory_order_relaxed);
    atomic_store_explicit(&sInternalSettingsEnabled, internalSettings, memory_order_relaxed);
    atomic_store_explicit(&sEmployeeEnabled, employee, memory_order_relaxed);
    atomic_store_explicit(&sHomebaseEnabled, homebase, memory_order_relaxed);
}

// -------------------------------------------------------------------------
// Known MobileConfig booleans.
// -------------------------------------------------------------------------

typedef BOOL (*FBTMessengerMCBoolFn)(void *context,
                                     uint64_t key,
                                     BOOL defaultValue,
                                     void *extra);

static FBTMessengerMCBoolFn orig_MSGCSessionedMobileConfigGetBoolean = NULL;

static BOOL FBTMessengerForceBooleanForKey(uint64_t key, BOOL *matched) {
    BOOL employee = FBTMessengerEmployeeEnabled();
    BOOL internalSettings =
        atomic_load_explicit(&sInternalSettingsEnabled, memory_order_relaxed);
    BOOL internalTools = FBTMessengerInternalToolsEnabled();
    BOOL homebase = atomic_load_explicit(&sHomebaseEnabled, memory_order_relaxed);

    if (employee &&
        (key == kMCFBFordIsEmployee || key == kMCSecretConversationIsEmployee)) {
        *matched = YES;
        return YES;
    }
    if (internalSettings && key == kMCFBFordCanAccessInternalSettings) {
        *matched = YES;
        return YES;
    }
    if (internalTools &&
        (key == kMCLabyrinthDevDebugUX ||
         key == kMCLabyrinthEBDebugMenu ||
         key == kMCLabyrinthEBDebugAdvancedMenu ||
         key == kMCLabyrinthEBDebugUserOverrides)) {
        *matched = YES;
        return YES;
    }
    if (homebase &&
        (key == kMCHomebaseMailboxSync ||
         key == kMCHomebaseTab ||
         key == kMCHomebaseCalendarRSVP ||
         key == kMCHomebaseListAddRow ||
         key == kMCHomebaseThreadSettings)) {
        *matched = YES;
        return YES;
    }

    *matched = NO;
    return NO;
}

static BOOL fbt_messenger_MobileConfigGetBoolean(void *context,
                                                  uint64_t key,
                                                  BOOL defaultValue,
                                                  void *extra) {
    BOOL original = orig_MSGCSessionedMobileConfigGetBoolean
        ? orig_MSGCSessionedMobileConfigGetBoolean(context, key, defaultValue, extra)
        : defaultValue;
    BOOL matched = NO;
    BOOL forced = FBTMessengerForceBooleanForKey(key, &matched);
    return matched ? forced : original;
}

static void FBTMessengerInstallMobileConfigHook(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct rebinding binding = {
            "MSGCSessionedMobileConfigGetBoolean",
            (void *)fbt_messenger_MobileConfigGetBoolean,
            (void **)&orig_MSGCSessionedMobileConfigGetBoolean,
        };
        rebind_symbols(&binding, 1);
        FBTLog(@"Messenger MobileConfig bool hook installed (fishhook only)");
    });
}

// -------------------------------------------------------------------------
// Exact Objective-C identity and provider hooks.
// -------------------------------------------------------------------------

typedef struct {
    const char *className;
    Class targetClass;
    IMP original;
} FBTMessengerHookDescriptor;

static FBTMessengerHookDescriptor sEmployeeGetters[] = {
    { "MBUISimpleParticipantModel", Nil, NULL },
    { "MBQPreviewParticipant", Nil, NULL },
    { "MSGParticipantContact", Nil, NULL },
    { "MSGMentionPlaceholderParticipant", Nil, NULL },
    { "MSGPublicChatParticipantAdapter", Nil, NULL },
    { "MSGPublicChatMemberAdapter", Nil, NULL },
};

static FBTMessengerHookDescriptor sEmployeeSetters[] = {
    { "FBWKWebView", Nil, NULL },
    { "FBWKWebViewDelegateAdaptor", Nil, NULL },
};

static FBTMessengerHookDescriptor sInternalToolProviders[] = {
    { "MSGEBDebugSettingsViewController", Nil, NULL },
    { "MSGEBDebugUserSettingsOverrideViewController", Nil, NULL },
};

static BOOL FBTMessengerEncodingMatches(Method method,
                                         const char *first,
                                         const char *second) {
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    return actual &&
        ((first && strcmp(actual, first) == 0) ||
         (second && strcmp(actual, second) == 0));
}

static FBTMessengerHookDescriptor *FBTMessengerDescriptorForReceiver(
    id receiver,
    FBTMessengerHookDescriptor *descriptors,
    size_t count) {
    Class receiverClass = object_getClass(receiver);
    for (Class current = receiverClass; current; current = class_getSuperclass(current)) {
        for (size_t index = 0; index < count; index++) {
            if (descriptors[index].targetClass == current) return &descriptors[index];
        }
    }
    return NULL;
}

static BOOL fbt_messenger_isEmployee(id self, SEL _cmd) {
    if (FBTMessengerEmployeeEnabled()) return YES;
    FBTMessengerHookDescriptor *descriptor = FBTMessengerDescriptorForReceiver(
        self,
        sEmployeeGetters,
        sizeof(sEmployeeGetters) / sizeof(sEmployeeGetters[0]));
    if (!descriptor || !descriptor->original) return NO;
    return ((BOOL (*)(id, SEL))descriptor->original)(self, _cmd);
}

static void fbt_messenger_setIsEmployee(id self, SEL _cmd, BOOL value) {
    FBTMessengerHookDescriptor *descriptor = FBTMessengerDescriptorForReceiver(
        self,
        sEmployeeSetters,
        sizeof(sEmployeeSetters) / sizeof(sEmployeeSetters[0]));
    if (!descriptor || !descriptor->original) return;
    ((void (*)(id, SEL, BOOL))descriptor->original)(
        self, _cmd, FBTMessengerEmployeeEnabled() ? YES : value);
}

static BOOL fbt_messenger_internalToolIsAvailable(id self, SEL _cmd, id context) {
    if (FBTMessengerInternalToolsEnabled()) return YES;
    FBTMessengerHookDescriptor *descriptor = FBTMessengerDescriptorForReceiver(
        self,
        sInternalToolProviders,
        sizeof(sInternalToolProviders) / sizeof(sInternalToolProviders[0]));
    if (!descriptor || !descriptor->original) return NO;
    return ((BOOL (*)(id, SEL, id))descriptor->original)(self, _cmd, context);
}

static void FBTMessengerInstallInstanceHooks(FBTMessengerHookDescriptor *descriptors,
                                              size_t count,
                                              SEL selector,
                                              IMP replacement,
                                              const char *firstEncoding,
                                              const char *secondEncoding) {
    for (size_t index = 0; index < count; index++) {
        FBTMessengerHookDescriptor *descriptor = &descriptors[index];
        if (descriptor->original) continue;
        Class cls = objc_getClass(descriptor->className);
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        if (!FBTMessengerEncodingMatches(method, firstEncoding, secondEncoding)) continue;
        descriptor->targetClass = cls;
        MSHookMessageEx(cls, selector, replacement, &descriptor->original);
    }
}

static void FBTMessengerInstallClassHooks(FBTMessengerHookDescriptor *descriptors,
                                           size_t count,
                                           SEL selector,
                                           IMP replacement,
                                           const char *firstEncoding,
                                           const char *secondEncoding) {
    for (size_t index = 0; index < count; index++) {
        FBTMessengerHookDescriptor *descriptor = &descriptors[index];
        if (descriptor->original) continue;
        Class cls = objc_getClass(descriptor->className);
        Class metaclass = cls ? object_getClass(cls) : Nil;
        Method method = metaclass ? class_getInstanceMethod(metaclass, selector) : NULL;
        if (!FBTMessengerEncodingMatches(method, firstEncoding, secondEncoding)) continue;
        descriptor->targetClass = metaclass;
        MSHookMessageEx(metaclass, selector, replacement, &descriptor->original);
    }
}

// -------------------------------------------------------------------------
// Native MobileConfig Objective-C readers.
//
// LightSpeedEngine performs many reads inside its own image. A fishhook on
// LightSpeedCore's import slot cannot observe those direct internal calls.
// Messenger 574 exposes the typed readers below through Objective-C dispatch,
// which lets us override the validated uint64 descriptor keys without writing
// to a signed __TEXT page.
// -------------------------------------------------------------------------

typedef struct {
    const char *className;
    const char *selectorName;
    const char *encoding;
    IMP replacement;
    IMP *originalStorage;
    BOOL installed;
} FBTMessengerMCObjectHook;

typedef struct { uint64_t rawValue; } FBTMessengerMCBoolParam;
typedef struct { uint64_t rawValue; } FBTMessengerMCSessionlessBoolParam;
typedef struct { uint64_t rawValue; } FBTMessengerMCSessionBasedBoolParam;

#define FBT_MESSENGER_DEFINE_MC_VALUE_HOOK(Name, ParamType) \
    static IMP s##Name##Original = NULL; \
    static BOOL fbt_messenger_##Name(id self, SEL _cmd, ParamType parameter) { \
        BOOL matched = NO; \
        BOOL forced = FBTMessengerForceBooleanForKey(parameter.rawValue, &matched); \
        if (matched) return forced; \
        IMP original = s##Name##Original; \
        return original \
            ? ((BOOL (*)(id, SEL, ParamType))original)(self, _cmd, parameter) \
            : NO; \
    }

#define FBT_MESSENGER_DEFINE_MC_VALUE_DEFAULT_HOOK(Name, ParamType) \
    static IMP s##Name##Original = NULL; \
    static BOOL fbt_messenger_##Name(id self, \
                                      SEL _cmd, \
                                      ParamType parameter, \
                                      BOOL defaultValue) { \
        BOOL matched = NO; \
        BOOL forced = FBTMessengerForceBooleanForKey(parameter.rawValue, &matched); \
        if (matched) return forced; \
        IMP original = s##Name##Original; \
        return original \
            ? ((BOOL (*)(id, SEL, ParamType, BOOL))original)( \
                self, _cmd, parameter, defaultValue) \
            : defaultValue; \
    }

#define FBT_MESSENGER_DEFINE_MC_VALUE_OPTIONS_HOOK(Name, ParamType) \
    static IMP s##Name##Original = NULL; \
    static BOOL fbt_messenger_##Name(id self, \
                                      SEL _cmd, \
                                      ParamType parameter, \
                                      id options) { \
        BOOL matched = NO; \
        BOOL forced = FBTMessengerForceBooleanForKey(parameter.rawValue, &matched); \
        if (matched) return forced; \
        IMP original = s##Name##Original; \
        return original \
            ? ((BOOL (*)(id, SEL, ParamType, id))original)( \
                self, _cmd, parameter, options) \
            : NO; \
    }

#define FBT_MESSENGER_DEFINE_MC_VALUE_OPTIONS_DEFAULT_HOOK(Name, ParamType) \
    static IMP s##Name##Original = NULL; \
    static BOOL fbt_messenger_##Name(id self, \
                                      SEL _cmd, \
                                      ParamType parameter, \
                                      id options, \
                                      BOOL defaultValue) { \
        BOOL matched = NO; \
        BOOL forced = FBTMessengerForceBooleanForKey(parameter.rawValue, &matched); \
        if (matched) return forced; \
        IMP original = s##Name##Original; \
        return original \
            ? ((BOOL (*)(id, SEL, ParamType, id, BOOL))original)( \
                self, _cmd, parameter, options, defaultValue) \
            : defaultValue; \
    }

// Each replacement owns the exact `old` stub returned for that class/method.
// A superclass replacement can therefore run with a subclass receiver without
// accidentally selecting the subclass trampoline again.
FBT_MESSENGER_DEFINE_MC_VALUE_HOOK(MCContextGetBool, FBTMessengerMCBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_HOOK(MCContextGetBoolWithoutLogging, FBTMessengerMCBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_DEFAULT_HOOK(MCContextGetBoolWithDefault, FBTMessengerMCBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_DEFAULT_HOOK(MCContextGetBoolWithoutLoggingWithDefault, FBTMessengerMCBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_OPTIONS_HOOK(MCContextGetBoolWithOptions, FBTMessengerMCBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_OPTIONS_DEFAULT_HOOK(MCContextGetBoolWithOptionsDefault, FBTMessengerMCBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_HOOK(MCSessionlessGetBool, FBTMessengerMCSessionlessBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_OPTIONS_HOOK(MCSessionlessGetBoolWithOptions, FBTMessengerMCSessionlessBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_HOOK(MCUserSessionGetBool, FBTMessengerMCSessionBasedBoolParam)
FBT_MESSENGER_DEFINE_MC_VALUE_OPTIONS_HOOK(MCUserSessionGetBoolWithOptions, FBTMessengerMCSessionBasedBoolParam)

static FBTMessengerMCObjectHook sMobileConfigObjectHooks[] = {
    {
        "FBMobileConfigContextManager",
        "getBool:",
        "B24@0:8{mc_bool_param_t=Q}16",
        (IMP)fbt_messenger_MCContextGetBool,
        &sMCContextGetBoolOriginal,
        NO,
    },
    {
        "FBMobileConfigContextManager",
        "getBoolWithoutLogging:",
        "B24@0:8{mc_bool_param_t=Q}16",
        (IMP)fbt_messenger_MCContextGetBoolWithoutLogging,
        &sMCContextGetBoolWithoutLoggingOriginal,
        NO,
    },
    {
        "FBMobileConfigContextManager",
        "getBool:withDefault:",
        "B28@0:8{mc_bool_param_t=Q}16B24",
        (IMP)fbt_messenger_MCContextGetBoolWithDefault,
        &sMCContextGetBoolWithDefaultOriginal,
        NO,
    },
    {
        "FBMobileConfigContextManager",
        "getBoolWithoutLogging:withDefault:",
        "B28@0:8{mc_bool_param_t=Q}16B24",
        (IMP)fbt_messenger_MCContextGetBoolWithoutLoggingWithDefault,
        &sMCContextGetBoolWithoutLoggingWithDefaultOriginal,
        NO,
    },
    {
        "FBMobileConfigContextManager",
        "getBool:withOptions:",
        "B32@0:8{mc_bool_param_t=Q}16@24",
        (IMP)fbt_messenger_MCContextGetBoolWithOptions,
        &sMCContextGetBoolWithOptionsOriginal,
        NO,
    },
    {
        "FBMobileConfigContextManager",
        "getBool:withOptions:withDefault:",
        "B36@0:8{mc_bool_param_t=Q}16@24B32",
        (IMP)fbt_messenger_MCContextGetBoolWithOptionsDefault,
        &sMCContextGetBoolWithOptionsDefaultOriginal,
        NO,
    },
    {
        "FBMobileConfigSessionlessContextManager",
        "getBool:",
        "B24@0:8{mc_sessionless_bool_param_t=Q}16",
        (IMP)fbt_messenger_MCSessionlessGetBool,
        &sMCSessionlessGetBoolOriginal,
        NO,
    },
    {
        "FBMobileConfigSessionlessContextManager",
        "getBool:withOptions:",
        "B32@0:8{mc_sessionless_bool_param_t=Q}16@24",
        (IMP)fbt_messenger_MCSessionlessGetBoolWithOptions,
        &sMCSessionlessGetBoolWithOptionsOriginal,
        NO,
    },
    {
        "FBMobileConfigUserSessionContextManager",
        "getBool:",
        "B24@0:8{mc_sessionbased_bool_param_t=Q}16",
        (IMP)fbt_messenger_MCUserSessionGetBool,
        &sMCUserSessionGetBoolOriginal,
        NO,
    },
    {
        "FBMobileConfigUserSessionContextManager",
        "getBool:withOptions:",
        "B32@0:8{mc_sessionbased_bool_param_t=Q}16@24",
        (IMP)fbt_messenger_MCUserSessionGetBoolWithOptions,
        &sMCUserSessionGetBoolWithOptionsOriginal,
        NO,
    },
};

static Method FBTMessengerDirectInstanceMethod(Class cls, SEL selector) {
    unsigned int methodCount = 0;
    Method *methods = cls ? class_copyMethodList(cls, &methodCount) : NULL;
    Method match = NULL;
    for (unsigned int index = 0; index < methodCount; index++) {
        if (sel_isEqual(method_getName(methods[index]), selector)) {
            match = methods[index];
            break;
        }
    }
    free(methods);
    return match;
}

static void FBTMessengerInstallMobileConfigObjectHooks(void) {
    for (size_t index = 0;
         index < sizeof(sMobileConfigObjectHooks) / sizeof(sMobileConfigObjectHooks[0]);
         index++) {
        FBTMessengerMCObjectHook *descriptor = &sMobileConfigObjectHooks[index];
        if (descriptor->installed) continue;

        Class cls = objc_getClass(descriptor->className);
        SEL selector = sel_registerName(descriptor->selectorName);
        Method method = FBTMessengerDirectInstanceMethod(cls, selector);
        const char *encoding = method ? method_getTypeEncoding(method) : NULL;
        if (!encoding || strcmp(encoding, descriptor->encoding) != 0) continue;

        MSHookMessageEx(cls,
                        selector,
                        descriptor->replacement,
                        descriptor->originalStorage);
        descriptor->installed = YES;
    }
}

static void FBTMessengerInstallKnownObjectHooks(void) {
    FBTMessengerInstallMobileConfigObjectHooks();

    FBTMessengerInstallInstanceHooks(
        sEmployeeGetters,
        sizeof(sEmployeeGetters) / sizeof(sEmployeeGetters[0]),
        sel_registerName("isEmployee"),
        (IMP)fbt_messenger_isEmployee,
        "B16@0:8",
        "c16@0:8");

    FBTMessengerInstallInstanceHooks(
        sEmployeeSetters,
        sizeof(sEmployeeSetters) / sizeof(sEmployeeSetters[0]),
        sel_registerName("setIsEmployee:"),
        (IMP)fbt_messenger_setIsEmployee,
        "v20@0:8B16",
        "v20@0:8c16");

    FBTMessengerInstallClassHooks(
        sInternalToolProviders,
        sizeof(sInternalToolProviders) / sizeof(sInternalToolProviders[0]),
        sel_registerName("isAvailable:"),
        (IMP)fbt_messenger_internalToolIsAvailable,
        "B24@0:8@16",
        "c24@0:8@16");
}

// -------------------------------------------------------------------------
// Compact long-press entry points: native tab bar and a conservatively
// identified Messenger logo/title image in the top navigation area. UIKit's
// context-menu interaction supplies the native iOS 26 Liquid Glass morph.
// -------------------------------------------------------------------------

static void FBTMessengerAttachLongPress(UIView *view) {
    FBTMessengerInstallQuickMenuInteraction(view);
}

static BOOL FBTMessengerStringContains(NSString *value, NSString *needle) {
    if (!value.length || !needle.length) return NO;
    return [value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL FBTMessengerIsTopLeadingView(UIView *view, UIWindow *window) {
    if (!view || !window || view.hidden || view.alpha < 0.05) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    if (CGRectIsEmpty(frame) || CGRectIsNull(frame)) return NO;
    CGFloat topLimit = window.safeAreaInsets.top + 72.0;
    if (CGRectGetMaxY(frame) > topLimit || CGRectGetMinX(frame) > 150.0) return NO;
    if (CGRectGetWidth(frame) < 16.0 || CGRectGetHeight(frame) < 16.0 ||
        CGRectGetWidth(frame) > 150.0 || CGRectGetHeight(frame) > 80.0) return NO;
    return YES;
}

static BOOL FBTMessengerLooksLikeLogoView(UIView *view, UIWindow *window) {
    if (!FBTMessengerIsTopLeadingView(view, window)) return NO;

    NSString *label = view.accessibilityLabel ?: @"";
    NSString *identifier = view.accessibilityIdentifier ?: @"";
    NSString *className = NSStringFromClass(view.class) ?: @"";
    BOOL saysMessenger = FBTMessengerStringContains(label, @"messenger") ||
        FBTMessengerStringContains(identifier, @"messenger") ||
        FBTMessengerStringContains(className, @"messenger");
    BOOL saysLogo = FBTMessengerStringContains(label, @"logo") ||
        FBTMessengerStringContains(identifier, @"logo") ||
        FBTMessengerStringContains(className, @"logo");
    BOOL saysWordmark = FBTMessengerStringContains(label, @"wordmark") ||
        FBTMessengerStringContains(identifier, @"wordmark") ||
        FBTMessengerStringContains(className, @"wordmark");
    return (saysMessenger && (saysLogo || saysWordmark)) ||
        [label caseInsensitiveCompare:@"Messenger"] == NSOrderedSame;
}

static UIView *FBTMessengerFindLogoView(UIView *root, UIWindow *window, NSUInteger depth) {
    if (!root || depth > 12) return nil;
    if (FBTMessengerLooksLikeLogoView(root, window)) return root;
    for (UIView *subview in root.subviews) {
        UIView *match = FBTMessengerFindLogoView(subview, window, depth + 1);
        if (match) return match;
    }
    return nil;
}

static UIViewController *FBTMessengerVisibleController(UIViewController *controller) {
    UIViewController *current = controller;
    while (current) {
        if (current.presentedViewController && !current.presentedViewController.isBeingDismissed) {
            current = current.presentedViewController;
            continue;
        }
        if ([current isKindOfClass:UINavigationController.class]) {
            current = ((UINavigationController *)current).visibleViewController;
            continue;
        }
        if ([current isKindOfClass:UITabBarController.class]) {
            current = ((UITabBarController *)current).selectedViewController;
            continue;
        }
        break;
    }
    return current;
}

static void FBTMessengerAttachLogoEntryPoint(id host, UIWindow *window) {
    UIViewController *selected = nil;
    SEL selectedSelector = sel_registerName("selectedViewController");
    if ([host respondsToSelector:selectedSelector]) {
        selected = ((id (*)(id, SEL))objc_msgSend)(host, selectedSelector);
    }
    UIViewController *visible = FBTMessengerVisibleController(selected ?: host);

    // Both identifiers are present in the mapped image. Prefer the exact
    // accessor when the visible controller exposes it; the geometry check
    // still prevents a same-named off-screen/debug view from becoming a gate.
    SEL logoSelector = sel_registerName("messengerLogoImageView");
    for (id owner in @[ visible ?: NSNull.null, host ?: NSNull.null ]) {
        if (owner == NSNull.null || ![owner respondsToSelector:logoSelector]) continue;
        id logoImage = ((id (*)(id, SEL))objc_msgSend)(owner, logoSelector);
        if ([logoImage isKindOfClass:UIView.class] &&
            FBTMessengerIsTopLeadingView(logoImage, window)) {
            FBTMessengerAttachLongPress(logoImage);
            return;
        }
    }

    UIView *titleView = visible.navigationItem.titleView;
    if (titleView && FBTMessengerLooksLikeLogoView(titleView, window)) {
        FBTMessengerAttachLongPress(titleView);
        return;
    }

    UINavigationBar *navigationBar = visible.navigationController.navigationBar;
    UIView *logo = FBTMessengerFindLogoView(navigationBar, window, 0);
    if (!logo && [host isKindOfClass:UIViewController.class]) {
        logo = FBTMessengerFindLogoView(((UIViewController *)host).view, window, 0);
    }
    if (logo) FBTMessengerAttachLongPress(logo);
}

static void FBTMessengerAttachEntryPoints(id host) {
    if (![host isKindOfClass:UIViewController.class]) return;
    UIViewController *hostController = (UIViewController *)host;
    UIWindow *window = hostController.view.window;
    if (!window) return;

    SEL tabBarSelector = sel_registerName("tabBar");
    if ([host respondsToSelector:tabBarSelector]) {
        id tabBar = ((id (*)(id, SEL))objc_msgSend)(host, tabBarSelector);
        if ([tabBar isKindOfClass:UIView.class]) FBTMessengerAttachLongPress(tabBar);
    }
    FBTMessengerAttachLogoEntryPoint(host, window);
}

typedef void (*FBTMessengerViewDidAppearFn)(id, SEL, BOOL);
static FBTMessengerViewDidAppearFn orig_MessengerTabBar_viewDidAppear = NULL;

static void fbt_messenger_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_MessengerTabBar_viewDidAppear) {
        orig_MessengerTabBar_viewDidAppear(self, _cmd, animated);
    }
    FBTMessengerInstallKnownObjectHooks();
    FBTMessengerAttachEntryPoints(self);

    __weak id weakHost = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id strongHost = weakHost;
        if (strongHost) FBTMessengerAttachEntryPoints(strongHost);
    });
}

static void FBTMessengerInstallTabHostHook(void) {
    if (orig_MessengerTabBar_viewDidAppear) return;
    Class cls = objc_getClass(
        "_TtC25MDSModernTabBarController25MDSModernTabBarController");
    SEL selector = sel_registerName("viewDidAppear:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!FBTMessengerEncodingMatches(method, "v20@0:8B16", "v20@0:8c16")) return;
    MSHookMessageEx(cls,
                    selector,
                    (IMP)fbt_messenger_viewDidAppear,
                    (IMP *)&orig_MessengerTabBar_viewDidAppear);
}

static void FBTMessengerRetryHooks(void) {
    FBTMessengerInstallKnownObjectHooks();
    FBTMessengerInstallTabHostHook();
}

static void FBTMessengerScheduleHookRetry(void) {
    BOOL wasScheduled = atomic_exchange_explicit(&sHooksScheduled,
                                                  true,
                                                  memory_order_relaxed);
    if (wasScheduled) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store_explicit(&sHooksScheduled, false, memory_order_relaxed);
        FBTMessengerRetryHooks();
    });
}

static void FBTMessengerImageAdded(__unused const struct mach_header *header,
                                    __unused intptr_t slide) {
    FBTMessengerScheduleHookRetry();
}

void FBTInstallMessengerFlags(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        FBTMessengerReloadPreferences();
        FBTMessengerInstallMobileConfigHook();
        FBTMessengerRetryHooks();
        _dyld_register_func_for_add_image(FBTMessengerImageAdded);

        [[NSNotificationCenter defaultCenter]
            addObserverForName:FBTNotificationPrefsChanged
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
            FBTMessengerReloadPreferences();
            FBTMessengerScheduleHookRetry();
        }];
    });
}
