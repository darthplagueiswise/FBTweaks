#import "FBTMessengerFlags.h"
#import "../../FBTDefaults.h"
#import "../../UI/FBTMessengerQuickMenu.h"
#include "../../../modules/fishhook/fishhook.h"
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stddef.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// -------------------------------------------------------------------------
// Messenger 574.0.0 (1035554267) — validated MobileConfig descriptors.
//
// These are packed descriptor keys, not offsets and not __TEXT patches.
// LightSpeedCore imports MSGCSessionedMobileConfigGetBoolean and
// LSShouldEnablePluginBasedOnMobileConfigParam from LightSpeedEngine. Both
// imports live in __DATA_CONST.__got as S_NON_LAZY_SYMBOL_POINTERS and have
// entries in LC_DYSYMTAB's indirect symbol table, so fishhook can rebind them
// without modifying a signed executable page.
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
static atomic_bool sHouseholdEnabled;
static atomic_bool sHooksScheduled;
static atomic_uint sObservedOverrideKinds;

enum {
    FBTMessengerObservedEmployee = 1u << 0,
    FBTMessengerObservedInternalSettings = 1u << 1,
    FBTMessengerObservedInternalTools = 1u << 2,
    FBTMessengerObservedHomebase = 1u << 3,
    FBTMessengerObservedHousehold = 1u << 4,
};

static BOOL FBTMessengerEmployeeEnabled(void) {
    return atomic_load_explicit(&sEmployeeEnabled, memory_order_relaxed);
}

static BOOL FBTMessengerInternalToolsEnabled(void) {
    return atomic_load_explicit(&sInternalToolsEnabled, memory_order_relaxed);
}

static BOOL FBTMessengerInternalSettingsEnabled(void) {
    return atomic_load_explicit(&sInternalSettingsEnabled, memory_order_relaxed);
}

static void FBTMessengerReloadPreferences(void) {
    BOOL internalTools = [FBTDefaults boolForKey:FBTKeyMessengerInternalToolsEnabled];
    BOOL internalSettings = internalTools ||
        [FBTDefaults boolForKey:FBTKeyMessengerInternalSettingsEnabled];
    BOOL employee = internalSettings ||
        [FBTDefaults boolForKey:FBTKeyEmployeeEnabled];
    BOOL household = [FBTDefaults boolForKey:FBTKeyMessengerHouseholdEnabled];
    BOOL homebase = household ||
        [FBTDefaults boolForKey:FBTKeyMessengerHomebaseEnabled];

    atomic_store_explicit(&sInternalToolsEnabled, internalTools, memory_order_relaxed);
    atomic_store_explicit(&sInternalSettingsEnabled, internalSettings, memory_order_relaxed);
    atomic_store_explicit(&sEmployeeEnabled, employee, memory_order_relaxed);
    atomic_store_explicit(&sHomebaseEnabled, homebase, memory_order_relaxed);
    atomic_store_explicit(&sHouseholdEnabled, household, memory_order_relaxed);
}

// -------------------------------------------------------------------------
// Known MobileConfig booleans.
// -------------------------------------------------------------------------

// LightSpeedCore does not pass the packed key in x1. Every mapped call site
// copies this 32-byte descriptor to the stack and passes a pointer to it:
//   x0 = session, x1 = descriptor, w2 = fallback, w3 = read options/logging.
// The previous uint64_t x1 declaration therefore compared a stack address to
// the packed key and could never match a requested override.
typedef struct {
    const char *configName;
    const char *parameterName;
    uint64_t rawValue;
    uint64_t unitType;
} FBTMessengerMCParameterDescriptor;

_Static_assert(sizeof(FBTMessengerMCParameterDescriptor) == 32,
               "Messenger MobileConfig descriptor ABI changed");
_Static_assert(offsetof(FBTMessengerMCParameterDescriptor, rawValue) == 16,
               "Messenger MobileConfig key offset changed");

typedef BOOL (*FBTMessengerMCBoolFn)(
    void *context,
    const FBTMessengerMCParameterDescriptor *parameter,
    BOOL defaultValue,
    BOOL readOptions);

static FBTMessengerMCBoolFn orig_MSGCSessionedMobileConfigGetBoolean = NULL;

static void FBTMessengerRecordObservedOverride(unsigned int kind,
                                                uint64_t key,
                                                const char *name) {
    unsigned int previous = atomic_fetch_or_explicit(&sObservedOverrideKinds,
                                                      kind,
                                                      memory_order_relaxed);
    if ((previous & kind) == 0) {
        FBTLog(@"Messenger override consumed: %s (0x%016llx)",
               name,
               (unsigned long long)key);
    }
}

static BOOL FBTMessengerForceBooleanForKey(uint64_t key, BOOL *matched) {
    BOOL employee = FBTMessengerEmployeeEnabled();
    BOOL internalSettings = FBTMessengerInternalSettingsEnabled();
    BOOL internalTools = FBTMessengerInternalToolsEnabled();
    BOOL homebase = atomic_load_explicit(&sHomebaseEnabled, memory_order_relaxed);
    BOOL household = atomic_load_explicit(&sHouseholdEnabled, memory_order_relaxed);

    if (employee &&
        (key == kMCFBFordIsEmployee || key == kMCSecretConversationIsEmployee)) {
        FBTMessengerRecordObservedOverride(FBTMessengerObservedEmployee,
                                            key,
                                            "employee");
        *matched = YES;
        return YES;
    }
    if (internalSettings && key == kMCFBFordCanAccessInternalSettings) {
        FBTMessengerRecordObservedOverride(FBTMessengerObservedInternalSettings,
                                            key,
                                            "internal-settings");
        *matched = YES;
        return YES;
    }
    if (internalTools &&
        (key == kMCLabyrinthDevDebugUX ||
         key == kMCLabyrinthEBDebugMenu ||
         key == kMCLabyrinthEBDebugAdvancedMenu ||
         key == kMCLabyrinthEBDebugUserOverrides)) {
        FBTMessengerRecordObservedOverride(FBTMessengerObservedInternalTools,
                                            key,
                                            "internal-tools");
        *matched = YES;
        return YES;
    }
    if (homebase &&
        (key == kMCHomebaseMailboxSync ||
         key == kMCHomebaseTab ||
         key == kMCHomebaseCalendarRSVP ||
         key == kMCHomebaseListAddRow)) {
        FBTMessengerRecordObservedOverride(FBTMessengerObservedHomebase,
                                            key,
                                            "homebase");
        *matched = YES;
        return YES;
    }
    // Messenger 574 has no standalone Household boolean. The verified local
    // Household paths are Homebase mailbox sync and the Homebase thread-
    // settings entry point; account membership itself remains server data.
    if (household &&
        (key == kMCHomebaseMailboxSync ||
         key == kMCHomebaseThreadSettings)) {
        FBTMessengerRecordObservedOverride(FBTMessengerObservedHousehold,
                                            key,
                                            "household");
        *matched = YES;
        return YES;
    }

    *matched = NO;
    return NO;
}

static BOOL fbt_messenger_MobileConfigGetBoolean(void *context,
                                                  const FBTMessengerMCParameterDescriptor *parameter,
                                                  BOOL defaultValue,
                                                  BOOL readOptions) {
    BOOL matched = NO;
    BOOL forced = FBTMessengerForceBooleanForKey(
        parameter ? parameter->rawValue : UINT64_C(0),
        &matched);
    if (matched) return forced;
    return orig_MSGCSessionedMobileConfigGetBoolean
        ? orig_MSGCSessionedMobileConfigGetBoolean(
              context, parameter, defaultValue, readOptions)
        : defaultValue;
}

// Preserve all four x-register arguments exactly as the original flags branch
// does. Narrowing x1..x3 to int32/BOOL would corrupt any pointer-sized payload
// on the fall-through path even though the return value itself is a BOOL.
typedef BOOL (*FBTMessengerEasyGatingBoolFn)(void *, void *, void *, void *);

static FBTMessengerEasyGatingBoolFn
    orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock = NULL;

static BOOL fbt_messenger_EasyGatingGetBoolean_Internal_DoNotUseOrMock(
    void *a0,
    void *a1,
    void *a2,
    void *a3) {
    if (FBTMessengerInternalToolsEnabled()) return YES;
    return orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock
        ? orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock(
              a0, a1, a2, a3)
        : NO;
}

// Messenger's direct equivalent of Facebook's
// FBShouldEnableInternalSettings import. Capstone validation of
// LSShouldEnablePluginBasedOnMobileConfigParam at LightSpeedEngine+0x1a5ce0:
//   x0 = MCI auth-data context
//   x1 = address of a tagged descriptor pointer (bit 0 is the fallback BOOL)
//   descriptor + 16 = packed uint64 MobileConfig key
//   w0 = BOOL result
// This catches the plugin eligibility decision itself, including the
// fb_ford.is_employee identity gate, rather than only changing a generic MC
// reader and hoping the settings plugin asks that import again.
typedef BOOL (*FBTMessengerPluginMobileConfigGateFn)(
    void *authDataContext,
    const uintptr_t *taggedParameter);

static FBTMessengerPluginMobileConfigGateFn
    orig_LSShouldEnablePluginBasedOnMobileConfigParam = NULL;

static uint64_t FBTMessengerPluginParameterKey(
    const uintptr_t *taggedParameter) {
    if (!taggedParameter) return UINT64_C(0);
    uintptr_t descriptorAddress =
        __atomic_load_n(taggedParameter, __ATOMIC_ACQUIRE) &
        ~(uintptr_t)1;
    if (!descriptorAddress) return UINT64_C(0);

    uint64_t key = UINT64_C(0);
    memcpy(&key,
           (const void *)(descriptorAddress +
                          offsetof(FBTMessengerMCParameterDescriptor, rawValue)),
           sizeof(key));
    return key;
}

static BOOL fbt_messenger_LSShouldEnablePluginBasedOnMobileConfigParam(
    void *authDataContext,
    const uintptr_t *taggedParameter) {
    BOOL matched = NO;
    BOOL forced = FBTMessengerForceBooleanForKey(
        FBTMessengerPluginParameterKey(taggedParameter),
        &matched);
    if (matched) return forced;
    return orig_LSShouldEnablePluginBasedOnMobileConfigParam
        ? orig_LSShouldEnablePluginBasedOnMobileConfigParam(
              authDataContext, taggedParameter)
        : (taggedParameter &&
           ((__atomic_load_n(taggedParameter, __ATOMIC_RELAXED) & 1u) != 0));
}

static atomic_bool sCImportHooksInstalled;
static atomic_bool sCImportStatusLogged;

static void FBTMessengerInstallCImportHooks(void) {
    if (atomic_exchange_explicit(&sCImportHooksInstalled,
                                 true,
                                 memory_order_relaxed)) {
        return;
    }

    struct rebinding rebindings[] = {
        {
            "MSGCSessionedMobileConfigGetBoolean",
            (void *)fbt_messenger_MobileConfigGetBoolean,
            (void **)&orig_MSGCSessionedMobileConfigGetBoolean,
        },
        {
            "LSShouldEnablePluginBasedOnMobileConfigParam",
            (void *)fbt_messenger_LSShouldEnablePluginBasedOnMobileConfigParam,
            (void **)&orig_LSShouldEnablePluginBasedOnMobileConfigParam,
        },
        {
            "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
            (void *)fbt_messenger_EasyGatingGetBoolean_Internal_DoNotUseOrMock,
            (void **)&orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock,
        },
    };
    int result = rebind_symbols(
        rebindings,
        sizeof(rebindings) / sizeof(rebindings[0]));
    FBTLog(@"Messenger import hooks registered: result=%d", result);
}

// -------------------------------------------------------------------------
// Exact Objective-C identity propagation hooks.
// -------------------------------------------------------------------------

// The original flags branch deliberately includes this exact propagation
// model. It is not the source of the current viewer's identity; the source is
// fb_ford.is_employee above. It remains useful for downstream Messenger UI
// that receives the viewer as a participant. Keep its own trampoline so a
// different participant class can never recurse through this original IMP.
typedef BOOL (*FBTMessengerBoolVoidFn)(id, SEL);
static FBTMessengerBoolVoidFn
    orig_MBUISimpleParticipantModel_isEmployee = NULL;

static BOOL fbt_messenger_MBUISimpleParticipantModel_isEmployee(
    id self,
    SEL _cmd) {
    return FBTMessengerEmployeeEnabled()
        ? YES
        : (orig_MBUISimpleParticipantModel_isEmployee
               ? orig_MBUISimpleParticipantModel_isEmployee(self, _cmd)
               : NO);
}

static BOOL FBTMessengerEncodingMatches(Method method,
                                         const char *first,
                                         const char *second) {
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    return actual &&
        ((first && strcmp(actual, first) == 0) ||
         (second && strcmp(actual, second) == 0));
}

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

typedef void (*FBTMessengerVoidBoolFn)(id, SEL, BOOL);
static FBTMessengerVoidBoolFn orig_FBWKWebView_setIsEmployee = NULL;
static FBTMessengerVoidBoolFn
    orig_FBWKWebViewDelegateAdaptor_setIsEmployee = NULL;

static void fbt_messenger_FBWKWebView_setIsEmployee(id self,
                                                     SEL _cmd,
                                                     BOOL value) {
    if (orig_FBWKWebView_setIsEmployee) {
        orig_FBWKWebView_setIsEmployee(
            self, _cmd, FBTMessengerEmployeeEnabled() ? YES : value);
    }
}

static void fbt_messenger_FBWKWebViewDelegateAdaptor_setIsEmployee(
    id self,
    SEL _cmd,
    BOOL value) {
    if (orig_FBWKWebViewDelegateAdaptor_setIsEmployee) {
        orig_FBWKWebViewDelegateAdaptor_setIsEmployee(
            self, _cmd, FBTMessengerEmployeeEnabled() ? YES : value);
    }
}

static void FBTMessengerInstallVoidBoolHook(const char *className,
                                            const char *selectorName,
                                            IMP replacement,
                                            IMP *original) {
    if (!className || !selectorName || !replacement || !original || *original) {
        return;
    }
    Class cls = objc_getClass(className);
    SEL selector = sel_registerName(selectorName);
    Method method = FBTMessengerDirectInstanceMethod(cls, selector);
    if (!FBTMessengerEncodingMatches(method,
                                     "v20@0:8B16",
                                     "v20@0:8c16")) {
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

typedef id (*FBTMessengerRageShakeInitFn)(id,
                                          SEL,
                                          id,
                                          id,
                                          id,
                                          id,
                                          id,
                                          id,
                                          BOOL,
                                          BOOL,
                                          BOOL,
                                          BOOL,
                                          BOOL,
                                          BOOL,
                                          id,
                                          NSInteger,
                                          NSInteger,
                                          BOOL);

static FBTMessengerRageShakeInitFn orig_LSRageShakeView_init = NULL;

static id fbt_messenger_LSRageShakeView_init(id self,
                                             SEL _cmd,
                                             id bugDescription,
                                             id textViewDelegate,
                                             id tapLinkHandler,
                                             id addMediaButtonTapHandler,
                                             id takeScreenshotButtonTapHandler,
                                             id recordScreenButtonTapHandler,
                                             BOOL showSuggestedProblemTags,
                                             BOOL isEmployee,
                                             BOOL showAssignToMeField,
                                             BOOL showReproStepsBox,
                                             BOOL showLoginAsUserPermissionField,
                                             BOOL isAiStudioTabEnabled,
                                             id selectedProblemTagsHandler,
                                             NSInteger minCharacterCount,
                                             NSInteger maxCharacterCount,
                                             BOOL isCharacterCountEnabled) {
    if (!orig_LSRageShakeView_init) return nil;
    return orig_LSRageShakeView_init(
        self,
        _cmd,
        bugDescription,
        textViewDelegate,
        tapLinkHandler,
        addMediaButtonTapHandler,
        takeScreenshotButtonTapHandler,
        recordScreenButtonTapHandler,
        showSuggestedProblemTags,
        FBTMessengerEmployeeEnabled() ? YES : isEmployee,
        showAssignToMeField,
        showReproStepsBox,
        showLoginAsUserPermissionField,
        isAiStudioTabEnabled,
        selectedProblemTagsHandler,
        minCharacterCount,
        maxCharacterCount,
        isCharacterCountEnabled);
}

typedef void (*FBTMessengerBloksLabDeeplinkFn)(id,
                                               SEL,
                                               id,
                                               id,
                                               BOOL,
                                               BOOL,
                                               BOOL,
                                               id,
                                               id);

static FBTMessengerBloksLabDeeplinkFn
    orig_BKBloksLabDeeplinkHelper_process = NULL;

static void fbt_messenger_BKBloksLabDeeplinkHelper_process(
    id self,
    SEL _cmd,
    id deeplink,
    id foaObjectSet,
    BOOL passPrototypeShortcode,
    BOOL useInternalNetworkCheck,
    BOOL isEmployee,
    id session,
    id containerConfigProvider) {
    if (!orig_BKBloksLabDeeplinkHelper_process) return;
    orig_BKBloksLabDeeplinkHelper_process(
        self,
        _cmd,
        deeplink,
        foaObjectSet,
        passPrototypeShortcode,
        FBTMessengerInternalToolsEnabled() ? YES : useInternalNetworkCheck,
        FBTMessengerEmployeeEnabled() ? YES : isEmployee,
        session,
        containerConfigProvider);
}

static void FBTMessengerInstallIdentityPropagationHooks(void) {
    if (!orig_MBUISimpleParticipantModel_isEmployee) {
        Class cls = objc_getClass("MBUISimpleParticipantModel");
        SEL selector = sel_registerName("isEmployee");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        if (FBTMessengerEncodingMatches(method,
                                        "B16@0:8",
                                        "c16@0:8")) {
            MSHookMessageEx(
                cls,
                selector,
                (IMP)fbt_messenger_MBUISimpleParticipantModel_isEmployee,
                (IMP *)&orig_MBUISimpleParticipantModel_isEmployee);
        }
    }

    FBTMessengerInstallVoidBoolHook(
        "FBWKWebView",
        "setIsEmployee:",
        (IMP)fbt_messenger_FBWKWebView_setIsEmployee,
        (IMP *)&orig_FBWKWebView_setIsEmployee);
    FBTMessengerInstallVoidBoolHook(
        "FBWKWebViewDelegateAdaptor",
        "setIsEmployee:",
        (IMP)fbt_messenger_FBWKWebViewDelegateAdaptor_setIsEmployee,
        (IMP *)&orig_FBWKWebViewDelegateAdaptor_setIsEmployee);

    if (!orig_LSRageShakeView_init) {
        Class cls = objc_getClass("LSRageShakeView");
        SEL selector = sel_registerName(
            "initWithBugDescription:textViewDelegate:tapLinkHandler:"
            "addMediaButtonTapHandler:takeScreenshotButtonTapHandler:"
            "recordScreenButtonTapHandler:showSuggestedProblemTags:isEmployee:"
            "showAssignToMeField:showReproStepsBox:"
            "showLoginAsUserPermissionField:isAiStudioTabEnabled:"
            "selectedProblemTagsHandler:minCharacterCount:maxCharacterCount:"
            "isCharacterCountEnabled:");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        const char *encoding = method ? method_getTypeEncoding(method) : NULL;
        const char *expected =
            "@116@0:8@16@24@?32@?40@?48@?56B64B68B72B76B80B84"
            "@?88q96q104B112";
        if (encoding && strcmp(encoding, expected) == 0) {
            MSHookMessageEx(cls,
                            selector,
                            (IMP)fbt_messenger_LSRageShakeView_init,
                            (IMP *)&orig_LSRageShakeView_init);
        }
    }

    if (!orig_BKBloksLabDeeplinkHelper_process) {
        Class cls = objc_getClass(
            "_TtC24BKBloksLabDeeplinkHelper24BKBloksLabDeeplinkHelper");
        Class metaclass = cls ? object_getClass(cls) : Nil;
        SEL selector = sel_registerName(
            "processDeeplinkWith:foaObjectSet:passPrototypeShortcode:"
            "useInternalNetworkCheck:isEmployee:session:"
            "containerConfigProvider:");
        Method method = metaclass
            ? class_getInstanceMethod(metaclass, selector)
            : NULL;
        if (FBTMessengerEncodingMatches(method,
                                        "v60@0:8@16@24B32B36B40@44@?52",
                                        NULL)) {
            MSHookMessageEx(
                metaclass,
                selector,
                (IMP)fbt_messenger_BKBloksLabDeeplinkHelper_process,
                (IMP *)&orig_BKBloksLabDeeplinkHelper_process);
        }
    }
}

// -------------------------------------------------------------------------
// Native MobileConfig Objective-C readers.
//
// LightSpeedEngine performs many reads inside its own image. Rebinding
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
    FBTMessengerInstallIdentityPropagationHooks();
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

static void FBTMessengerRefreshSettingsController(UIViewController *controller) {
    if (!controller) return;

    Class settingsClass = objc_getClass("MSGSettingsViewController");
    SEL refreshSelector = sel_registerName("_refreshData");
    if (settingsClass &&
        [controller isKindOfClass:settingsClass] &&
        [controller respondsToSelector:refreshSelector]) {
        Method method = class_getInstanceMethod(settingsClass, refreshSelector);
        if (FBTMessengerEncodingMatches(method, "v16@0:8", NULL)) {
            ((void (*)(id, SEL))objc_msgSend)(controller, refreshSelector);
        }
    }

    for (UIViewController *child in controller.childViewControllers) {
        FBTMessengerRefreshSettingsController(child);
    }
    UIViewController *presented = controller.presentedViewController;
    if (presented && !presented.isBeingDismissed) {
        FBTMessengerRefreshSettingsController(presented);
    }
}

static void FBTMessengerRefreshVisibleSettings(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha < 0.05) continue;
            FBTMessengerRefreshSettingsController(window.rootViewController);
        }
    }
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

    if (atomic_load_explicit(&sCImportHooksInstalled,
                             memory_order_relaxed) &&
        !atomic_exchange_explicit(&sCImportStatusLogged,
                                  true,
                                  memory_order_relaxed)) {
        FBTLog(@"Messenger imports rebound: mobileConfig=%d pluginIdentity=%d easyGating=%d",
               orig_MSGCSessionedMobileConfigGetBoolean != NULL,
               orig_LSShouldEnablePluginBasedOnMobileConfigParam != NULL,
               orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock != NULL);
    }
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

static void FBTMessengerImageAdded(const struct mach_header *header,
                                    __unused intptr_t slide) {
    (void)header;
    FBTMessengerScheduleHookRetry();
}

void FBTInstallMessengerFlags(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        FBTMessengerReloadPreferences();
        FBTMessengerInstallCImportHooks();
        FBTMessengerRetryHooks();
        _dyld_register_func_for_add_image(FBTMessengerImageAdded);

        [[NSNotificationCenter defaultCenter]
            addObserverForName:FBTNotificationPrefsChanged
                        object:nil
                         queue:nil
                    usingBlock:^(__unused NSNotification *notification) {
            FBTMessengerReloadPreferences();
            FBTMessengerScheduleHookRetry();
            dispatch_async(dispatch_get_main_queue(), ^{
                FBTMessengerRefreshVisibleSettings();
            });
        }];
    });
}
