#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import "FBTMobileConfigRuntime.h"
#import "FBTNativeMobileConfigOverrides.h"
#import "FBTMobileConfigFetchDiagnostics.h"
#import "FBTMobileConfigDebugUIHooks.h"
#import "FBTNamesResponseSummary.h"
#import "../Settings/FBTNamesDiagnosticsViewController.h"
#import "../Settings/FBTLocalConfigViewController.h"
#import "FBTMobileConfigResponseCapture.h"
#import "FBTMobileConfigQueryContext.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <string.h>
#include <string>
#include <functional>
#include <memory>
#include <vector>
#include "FBTQERequestOptionsCore.hpp"
#import "FBTQERequestOptions.h"
#include <dlfcn.h>
#include <mach-o/loader.h>
#include "../../modules/fishhook/fishhook.h"

// The advanced native MobileConfig UI lives in FBRarelyUsedFramework. The
// selected-param method receives two const std::string references; ObjC++ is
// therefore required to retain a safe copy for one controlled retry.
//
// This module never fabricates QE metadata. It warms local readers/contexts,
// suppresses only the first exact transient param-info alert, retries the same
// typed selection once, and preserves the native alert on the second failure.
// The second alert receives an explicit local FBT override fallback.

typedef void (*FBTViewDidLoadOrig)(id, SEL);
typedef void (*FBTSelectParamOrig)(id, SEL,
                                   const std::string &,
                                   int,
                                   const std::string &,
                                   long long,
                                   NSString *);
typedef void (*FBTPresentViewControllerOrig)(id, SEL,
                                              UIViewController *,
                                              BOOL,
                                              void (^ _Nullable)(void));

// ABI verificada nos três call sites ARM64: os chamadores testam w0 como bool.
typedef bool (*FBTQEInfoFetchOrig)(void *, void *, const std::string &,
                                   const std::string &, const void *, void *, void *);
typedef void (*FBTQEInfoRefreshNamesOrig)(void *, bool, std::function<void(bool)>);

struct FBTStdVectorLayout {
    const void *begin;
    const void *end;
    const void *capacity;
};

static BOOL FBTStdVectorHasElements(const void *opaqueVector) {
    if (!opaqueVector) return NO;
    const FBTStdVectorLayout *layout = (const FBTStdVectorLayout *)opaqueVector;
    return layout->begin != NULL && layout->end != NULL && layout->begin != layout->end;
}
typedef NSError *(*FBTNSErrorInitOrig)(id, SEL, NSString *, NSInteger, NSDictionary *);

static FBTViewDidLoadOrig orig_FBMobileConfigDebug_viewDidLoad = NULL;
static FBTSelectParamOrig orig_FBMobileConfigDebug_selectParam = NULL;
static FBTPresentViewControllerOrig orig_FBMobileConfigDebug_present = NULL;
static BOOL sBundleObserverInstalled = NO;
static BOOL sQEInfoFetchImportHookInstalled = NO;
static BOOL sQEInfoFetchBindingRegistered = NO;
static int sQEInfoFetchRebindStatus = -1;
static BOOL sQEInfoRefreshNamesImportHookInstalled = NO;
static BOOL sQEInfoNamesBindingRegistered = NO;
static int sQEInfoNamesRebindStatus = -1;
static BOOL sNSErrorInitHookInstalled = NO;
static thread_local NSUInteger sQEInfoFetchDepth = 0;
static thread_local BOOL sRecordingQEInfoNSError = NO;
static FBTQEInfoFetchOrig orig_FBMobileConfigQEInfoFetch = NULL;
static FBTQEInfoRefreshNamesOrig orig_FBMobileConfigQEInfoRefreshNames = NULL;
static FBTNSErrorInitOrig orig_NSError_initWithDomain = NULL;
static char kFBTMCSelectionKey;
static NSDictionary *sLatestNativeUIContexts;
static void (*orig_FBMobileConfigDebug_selectItem)(id, SEL, id);
static void (*sOriginalForceNameAction)(id, SEL);
static NSString *sForceNameActionFailure;

@interface FBTMobileConfigViewController : UITableViewController
@end

@interface UINavigationController (FBTMobileConfigFallback)
- (void)fbt_closeMobileConfigFallback;
@end

@implementation UINavigationController (FBTMobileConfigFallback)
- (void)fbt_closeMobileConfigFallback {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

@interface FBTMCSelection : NSObject {
@public
    std::string _param;
    std::string _configName;
    int _key;
    long long _backendType;
    NSString *_backendName;
    NSUInteger _retryCount;
    NSInteger _lastHTTPStatus;
}
- (instancetype)initWithParam:(const std::string &)param
                          key:(int)key
                   configName:(const std::string &)configName
                  backendType:(long long)backendType
                  backendName:(NSString *)backendName;
@end

@implementation FBTMCSelection
- (instancetype)initWithParam:(const std::string &)param
                          key:(int)key
                   configName:(const std::string &)configName
                  backendType:(long long)backendType
                  backendName:(NSString *)backendName {
    self = [super init];
    if (self) {
        _param = param;
        _configName = configName;
        _key = key;
        _backendType = backendType;
        _backendName = [backendName copy];
        _retryCount = 0;
    }
    return self;
}
@end

static NSString *FBTStringFromStdString(const std::string &value) {
    if (value.empty()) return @"";
    NSString *text = [[NSString alloc] initWithBytes:value.data()
                                              length:value.size()
                                            encoding:NSUTF8StringEncoding];
    return text ?: @"<non-UTF8>";
}

static NSError *fbt_NSError_initWithDomain(id self, SEL _cmd, NSString *domain,
                                            NSInteger code, NSDictionary *userInfo) {
    NSError *error = orig_NSError_initWithDomain
        ? orig_NSError_initWithDomain(self, _cmd, domain, code, userInfo) : nil;
    if (sQEInfoFetchDepth > 0 && !sRecordingQEInfoNSError &&
        [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) {
        NSMutableDictionary *details = [NSMutableDictionary dictionary];
        if (domain.length) details[@"error_domain"] = domain;
        details[@"error_code"] = @(code);
        id message = userInfo[NSLocalizedDescriptionKey] ?: userInfo[NSLocalizedFailureReasonErrorKey];
        if ([message isKindOfClass:[NSString class]]) details[@"message"] = message;
        for (NSString *key in @[@"statusCode", @"httpStatusCode", @"responseStatusCode", @"tigonStatusCode"]) {
            id status = userInfo[key];
            if ([status isKindOfClass:[NSNumber class]]) { details[@"http_status"] = status; break; }
            if ([status isKindOfClass:[NSString class]]) {
                NSInteger parsed = [status integerValue];
                if (parsed >= 100 && parsed <= 599) { details[@"http_status"] = @(parsed); break; }
            }
        }
        sRecordingQEInfoNSError = YES;
        FBTMobileConfigFetchDiagnosticsRecord(@"native_network_error", details);
        sRecordingQEInfoNSError = NO;
    }
    return error;
}

static void FBTInstallNSErrorMetadataHook(void) {
    if (!FBTQEInvasiveHooksAllowed()) return; // Never hook NSError across all of Facebook for QE diagnostics.
    if (sNSErrorInitHookInstalled) return;
    Class cls = objc_getClass("NSError");
    SEL sel = @selector(initWithDomain:code:userInfo:);
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!method || method_getNumberOfArguments(method) != 5) return;
    MSHookMessageEx(cls, sel, (IMP)fbt_NSError_initWithDomain,
                    (IMP *)&orig_NSError_initWithDomain);
    sNSErrorInitHookInstalled = (orig_NSError_initWithDomain != NULL);
    FBTMobileConfigFetchDiagnosticsRecord(@"native_error_hook", @{@"hook_installed": @(sNSErrorInitHookInstalled)});
}

static bool fbt_FBMobileConfigQEInfoFetch(void *manager, void *query,
                                          const std::string &arg2,
                                          const std::string &arg3,
                                          const void *metaMap,
                                          void *universeInfos,
                                          void *gkInfos) {
    if (!orig_FBMobileConfigQEInfoFetch) return false;
    FBTMobileConfigResponseCaptureArm(@"qe_info_param_fetch");
    FBTMobileConfigFetchDiagnosticsRecord(@"qe_info_request_started", @{
        @"arg2": FBTStringFromStdString(arg2), @"arg3": FBTStringFromStdString(arg3)
    });
    CFTimeInterval started = CACurrentMediaTime();
    NSArray<FBTMobileConfigQueryContext *> *matchingQueries = [FBTMobileConfigQueryContext
        contextsMatchingConfig:FBTStringFromStdString(arg2) param:FBTStringFromStdString(arg3)];
    void *queryScope = FBTMobileConfigFetcherCaptureBeginScope();
    ++sQEInfoFetchDepth;
    bool result = false;
    try {
        result = orig_FBMobileConfigQEInfoFetch(manager, query, arg2, arg3,
                                                metaMap, universeInfos, gkInfos);
    } catch (...) {
        FBTMobileConfigFetcherCaptureEndScope(queryScope);
        --sQEInfoFetchDepth;
        FBTMobileConfigFetchDiagnosticsRecord(@"qe_info_request_exception", @{
            @"arg2": FBTStringFromStdString(arg2), @"arg3": FBTStringFromStdString(arg3)
        });
        throw;
    }
    NSInteger httpStatus = FBTMobileConfigFetcherCaptureEndScope(queryScope);
    for (FBTMobileConfigQueryContext *context in matchingQueries) context.httpStatus = httpStatus;
    --sQEInfoFetchDepth;
    FBTMobileConfigFetchDiagnosticsRecord(@"qe_info_request_returned", @{
        @"arg2": FBTStringFromStdString(arg2), @"arg3": FBTStringFromStdString(arg3),
        @"fetch_result": @(result), @"http_status": @(httpStatus), @"matched_ui_query_count": @(matchingQueries.count), @"duration_ms": @((CACurrentMediaTime() - started) * 1000.0),
        @"output_universe_nonempty": @(FBTStdVectorHasElements(universeInfos)),
        @"output_gk_nonempty": @(FBTStdVectorHasElements(gkInfos)),
        @"metamap_argument_present": @(metaMap != NULL)
    });
    return result;
}

static void FBTInstallQEInfoFetchImportHook(void) {
    if (!FBTQEInvasiveHooksAllowed()) return;
    if (sQEInfoFetchImportHookInstalled ||
        ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    FBTInstallNSErrorMetadataHook();
    // fishhook removes Mach-O's leading underscore, so _ZN... is the Itanium name.
    struct rebinding binding = {
        "_ZN12mobileconfig27FBMobileConfigQEInfoManager24fetchQEInfoSynchronouslyERNS_31FBMobileConfigQEInfoQueryParamsERKNSt3__112basic_stringIcNS3_11char_traitsIcEENS3_9allocatorIcEEEESB_RKNS3_10shared_ptrINS_21FBMobileConfigMetaMapEEERNS3_6vectorINS_28FBMobileConfigQEUniverseInfoENS7_ISI_EEEERNSH_INS_20FBMobileConfigGKInfoENS7_ISM_EEEE",
        (void *)fbt_FBMobileConfigQEInfoFetch,
        (void **)&orig_FBMobileConfigQEInfoFetch
    };
    if (!sQEInfoFetchBindingRegistered) {
        sQEInfoFetchRebindStatus = rebind_symbols(&binding, 1);
        sQEInfoFetchBindingRegistered = (sQEInfoFetchRebindStatus == 0);
    }
    int status = sQEInfoFetchRebindStatus;
    sQEInfoFetchImportHookInstalled = (orig_FBMobileConfigQEInfoFetch != NULL &&
                                        orig_FBMobileConfigQEInfoFetch != fbt_FBMobileConfigQEInfoFetch);
    FBTMobileConfigFetchDiagnosticsRecord(@"qe_info_import_hook", @{
        @"hook_installed": @(sQEInfoFetchImportHookInstalled), @"rebind_status": @(status)
    });
}

static void fbt_FBMobileConfigQEInfoRefreshNames(void *manager, bool force,
        std::function<void(bool)> completion) {
    if (!orig_FBMobileConfigQEInfoRefreshNames) return;
    FBTMobileConfigResponseCaptureArm(force ? @"force_name_download" : @"qe_info_name_refresh");
    FBTMobileConfigFetchDiagnosticsRecord(@"name_download_started", @{
        @"force": @(force),
        @"capture_reason": force ? @"force_name_download" : @"qe_info_name_refresh"
    });
    std::shared_ptr<std::function<void(bool)>> callback =
        std::make_shared<std::function<void(bool)>>(std::move(completion));
    std::function<void(bool)> wrapped = [callback](bool success) {
        FBTMobileConfigFetchDiagnosticsRecord(@"name_download_completed", @{
            @"download_success": @(success)
        });
        if (callback && *callback) (*callback)(success);
    };
    try {
        orig_FBMobileConfigQEInfoRefreshNames(manager, force, std::move(wrapped));
    } catch (...) {
        FBTMobileConfigFetchDiagnosticsRecord(@"name_download_exception", @{ @"force": @(force) });
        throw;
    }
}

static void FBTInstallQEInfoRefreshNamesImportHook(void) {
    if (!FBTQEInvasiveHooksAllowed()) return;
    if (sQEInfoRefreshNamesImportHookInstalled ||
        ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;
    struct rebinding binding = {
        "_ZN12mobileconfig27FBMobileConfigQEInfoManager12refreshNamesEbNSt3__18functionIFvbEEE",
        (void *)fbt_FBMobileConfigQEInfoRefreshNames,
        (void **)&orig_FBMobileConfigQEInfoRefreshNames
    };
    if (!sQEInfoNamesBindingRegistered) {
        sQEInfoNamesRebindStatus = rebind_symbols(&binding, 1);
        sQEInfoNamesBindingRegistered = (sQEInfoNamesRebindStatus == 0);
    }
    int status = sQEInfoNamesRebindStatus;
    sQEInfoRefreshNamesImportHookInstalled =
        (orig_FBMobileConfigQEInfoRefreshNames != NULL &&
         orig_FBMobileConfigQEInfoRefreshNames != fbt_FBMobileConfigQEInfoRefreshNames);
    FBTMobileConfigFetchDiagnosticsRecord(@"name_download_import_hook", @{
        @"hook_installed": @(sQEInfoRefreshNamesImportHookInstalled),
        @"rebind_status": @(status)
    });
}

static BOOL FBTMCUIEncodingEquals(Class cls, SEL sel, const char *expected) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    return actual && expected && strcmp(actual, expected) == 0;
}

static void FBTForceNameAction(id object, SEL selector) {
    // REA: performNameDownload -> refreshNames -> asyncFetch is synchronous
    // up to dispatch. An unrelated/later QE request cannot consume this scope.
    fbt_qe_options::Scope scope(fbt_qe_options::sessionProfile());
    if (sOriginalForceNameAction) sOriginalForceNameAction(object, selector);
}

static void FBTInstallForceNameActionHook(void) {
    if (sOriginalForceNameAction) return;
    Class cls = objc_getClass("FBMobileConfigAdvancedSettingsViewController");
    if (!cls) { sForceNameActionFailure = @"Abra Advanced Settings para carregar o controller."; return; }
    @synchronized(cls) {
        if (sOriginalForceNameAction) return;
        SEL selector = sel_registerName("performNameDownload");
        Method method = class_getInstanceMethod(cls, selector);
        IMP implementation = method ? method_getImplementation(method) : NULL;
        Dl_info info = {};
        if (!FBTMCUIEncodingEquals(cls, selector, "v16@0:8") || !implementation ||
            !dladdr((void *)implementation, &info) || !info.dli_fbase || !info.dli_fname ||
            strcmp(strrchr(info.dli_fname, '/') ? strrchr(info.dli_fname, '/') + 1 : info.dli_fname,
                "FBRarelyUsedFramework") != 0 ||
            (uintptr_t)implementation - (uintptr_t)info.dli_fbase != 0x211e78) {
            sForceNameActionFailure = @"Controller/assinatura/IMP incompatível com a imagem analisada."; return;
        }
        const auto header = (const mach_header_64 *)info.dli_fbase;
        const unsigned char expected[16] = {0x4c,0x4c,0x44,0x83,0x55,0x55,0x31,0x44,
            0xa1,0xfa,0xce,0x46,0x1b,0xbe,0x10,0xaa};
        BOOL uuidMatches = NO;
        if (header->magic == MH_MAGIC_64 && header->ncmds < 4096 && header->sizeofcmds < 16 * 1024 * 1024) {
            const char *cursor = (const char *)(header + 1), *end = cursor + header->sizeofcmds;
            for (uint32_t i = 0; i < header->ncmds && end - cursor >= (ptrdiff_t)sizeof(load_command); ++i) {
                const auto cmd = (const load_command *)cursor;
                if (cmd->cmdsize < sizeof(load_command) || cmd->cmdsize > (size_t)(end - cursor)) break;
                if (cmd->cmd == LC_UUID && cmd->cmdsize >= sizeof(uuid_command)) {
                    uuidMatches = memcmp(((const uuid_command *)cmd)->uuid, expected, 16) == 0; break;
                }
                cursor += cmd->cmdsize;
            }
        }
        if (!uuidMatches) { sForceNameActionFailure = @"UUID RarelyUsed diferente da imagem analisada."; return; }
        sOriginalForceNameAction = (void (*)(id, SEL))implementation;
        method_setImplementation(method, (IMP)FBTForceNameAction);
        sForceNameActionFailure = nil;
    }
}

static void FBTMobileConfigDebugWarmup(void) {
    FBTMobileConfigResponseCaptureInstall();
    FBTInstallQEInfoRefreshNamesImportHook();
    FBTInstallQEInfoFetchImportHook();
    // Diagnostics may install observers without enabling warmup behavior.
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) return;
    // Post-launch/user-triggered only. Installing the fishhooks is safe here;
    // capture/override behavior remains controlled by live preferences.
    FBTMobileConfigSetSessionActive(YES);
    FBTInstallNativeMobileConfigContextCapture();
    FBTMobileConfigReloadPrefs();
}

static void FBTCallOriginalSelection(id controller, SEL selector, FBTMCSelection *selection) {
    if (!controller || !selection || !orig_FBMobileConfigDebug_selectParam) return;
    void *scope = FBTMobileConfigFetcherCaptureBeginScope();
    @try {
        try {
            orig_FBMobileConfigDebug_selectParam(controller, selector, selection->_param,
                selection->_key, selection->_configName, selection->_backendType, selection->_backendName);
        } catch (...) {
            selection->_lastHTTPStatus = FBTMobileConfigFetcherCaptureEndScope(scope);
            scope = nullptr;
            throw;
        }
    } @finally {
        if (scope) selection->_lastHTTPStatus = FBTMobileConfigFetcherCaptureEndScope(scope);
    }
}

static void FBTOpenLocalMobileConfigFallback(UIViewController *presenter) {
    FBTMCSelection *selection = objc_getAssociatedObject(presenter, &kFBTMCSelectionKey);
    FBTMobileConfigQueryContext *context = [FBTMobileConfigQueryContext contextForOwner:presenter];
    NSString *query = context.configName ?: (selection ? FBTStringFromStdString(selection->_configName) : @"");
    FBTLocalConfigViewController *local = [[FBTLocalConfigViewController alloc] initWithSearchQuery:query];
    if (!local) return;

    if (presenter.navigationController) {
        [presenter.navigationController pushViewController:local animated:YES];
        return;
    }

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:local];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    local.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                     target:nav
                                                     action:@selector(fbt_closeMobileConfigFallback)];
    [presenter presentViewController:nav animated:YES completion:nil];
}

static void FBTOpenNativeLocalCatalog(id controller, SEL selector) {
    FBTOpenLocalMobileConfigFallback(controller);
}

// Add a route to the in-app diagnostics while preserving native actions.
static void FBTAddNamesDiagnosticsAction(UIAlertController *alert) {
    for (UIAlertAction *action in alert.actions) if ([action.title isEqual:@"Diagnóstico detalhado"]) return;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Diagnóstico detalhado" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIViewController *presenter = weakAlert.presentingViewController;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (presenter.presentedViewController == weakAlert && weakAlert) {
                [presenter dismissViewControllerAnimated:YES completion:^{ FBTPresentNamesDiagnostics(presenter); }];
            } else FBTPresentNamesDiagnostics(presenter);
        });
    }]];
}

typedef UIAlertController *(*FBTNamesAlertFactoryFn)(id, SEL, NSString *, NSString *, UIAlertControllerStyle);
static FBTNamesAlertFactoryFn sOriginalNamesAlertFactory;
static UIAlertController *FBTNamesAlertFactory(id cls, SEL selector, NSString *title, NSString *message, UIAlertControllerStyle style) {
    UIAlertController *alert = sOriginalNamesAlertFactory(cls, selector, title, message, style);
    if (![FBTDefaults boolForKey:FBTKeyMasterEnabled] ||
        [message rangeOfString:@"Failed to download names. Please try again."].location == NSNotFound || !message.length) return alert;
    NSDictionary *snapshot = FBTMobileConfigFetchDiagnosticsSnapshot();
    NSDictionary *latest = nil;
    for (NSDictionary *event in [snapshot[@"events"] reverseObjectEnumerator]) {
        if ([event[@"process_session_id"] isEqual:snapshot[@"process_session_id"]] &&
            [event[@"event"] isEqual:@"names_transport_diagnostic"] &&
            [event[@"capture_reason"] isEqual:@"mobileconfig_qe_info"]) { latest = event; break; }
    }
    alert.title = @"Download de nomes não concluído";
    NSDictionary *advice = FBTNamesDiagnosticAdvice(latest ?: @{});
    NSString *extra = @"Abra o diagnóstico para conferir a resposta do servidor. O mapa local continua disponível.";
    if ([advice[@"classification"] isEqual:@"server_eligibility"]) {
        extra = [NSString stringWithFormat:@"Última rejeição capturada (pedido %@):\n%@\n\n%@", latest[@"request_id"] ?: @"?", latest[@"server_error_message"] ?: @"", advice[@"explanation"]];
    }
    alert.message = [message stringByAppendingFormat:@"\n\n%@", extra];
    FBTAddNamesDiagnosticsAction(alert);
    return alert;
}
static void FBTInstallNamesAlertReporting(void) {
    if (!FBTQEInvasiveHooksAllowed()) return; // Avoid a global UIAlertController metaclass hook.
    @synchronized(UIAlertController.class) {
        if (sOriginalNamesAlertFactory) return;
        Class meta = object_getClass(UIAlertController.class);
        SEL selector = @selector(alertControllerWithTitle:message:preferredStyle:);
        Method method = class_getInstanceMethod(meta, selector);
        if (method && method_getNumberOfArguments(method) == 5)
            MSHookMessageEx(meta, selector, (IMP)FBTNamesAlertFactory, (IMP *)&sOriginalNamesAlertFactory);
    }
}

static BOOL FBTIsTransientParamInfoAlert(UIViewController *controller) {
    if (![controller isKindOfClass:[UIAlertController class]]) return NO;
    NSString *title = ((UIAlertController *)controller).title ?: @"";
    return [title hasPrefix:@"Failed to fetch param info from server"];
}

static void FBTAddLocalFallbackAction(UIAlertController *alert, UIViewController *presenter) {
    for (UIAlertAction *action in alert.actions) {
        if ([action.title isEqualToString:@"Open FBT Local Override"]) return;
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Open FBT Local Override"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        FBTOpenLocalMobileConfigFallback(presenter);
    }]];
}

// Capture the managers already owned by the native UI without enabling readers.
// The six-object struct is present in the supplied initializer's ObjC encoding.
static void FBTCaptureNativeUIManagers(id controller) {
    for (Class cls = [controller class]; cls && cls != [UIViewController class]; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; ++i) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type) continue;
            NSUInteger encodedSize = 0;
            const char *structPrefix = "{_FBMobileConfigContextManagers=";
            BOOL managersStruct = strcmp(ivar_getName(ivars[i]), "_contextManagers") == 0 &&
                strncmp(type, structPrefix, strlen(structPrefix)) == 0;
            if (managersStruct) NSGetSizeAndAlignment(type, &encodedSize, NULL);
            if (managersStruct && encodedSize == 6 * sizeof(void *)) {
                ptrdiff_t offset = ivar_getOffset(ivars[i]);
                if (offset < 0 || (size_t)offset + 6 * sizeof(void *) > class_getInstanceSize([controller class])) continue;
                __unsafe_unretained id managers[6] = {};
                memcpy((void *)managers, (const char *)(__bridge const void *)controller + offset, sizeof(managers));
                NSMutableDictionary *status = [NSMutableDictionary dictionary];
                NSArray *labels = @[@"sessionless", @"session", @"admin_id", @"ad_account_id", @"page_id", @"wearable_owner_id"];
                for (unsigned int j = 0; j < 6; ++j) {
                    id manager = managers[j];
                    FBTNativeMobileConfigRegisterContext(manager);
                    FBTNativeMobileConfigRegisterOverrideObject(manager);
                    Method valid = manager ? class_getInstanceMethod([manager class], sel_registerName("hasValidManager")) : NULL;
                    BOOL ready = valid && strcmp(method_getTypeEncoding(valid), "B16@0:8") == 0 &&
                        ((BOOL (*)(id, SEL))objc_msgSend)(manager, sel_registerName("hasValidManager"));
                    status[labels[j]] = @{@"context_present": @(manager != nil), @"manager_ready": @(ready)};
                    if (ready) FBTMobileConfigFetcherObserveUIContext(manager, labels[j]);
                }
                @synchronized([FBTMCSelection class]) { sLatestNativeUIContexts = [status copy]; }
            } else if (type[0] == '@' && strstr(type, "MobileConfig") && strstr(type, "Manager")) {
                id manager = object_getIvar(controller, ivars[i]);
                FBTNativeMobileConfigRegisterContext(manager);
                FBTNativeMobileConfigRegisterOverrideObject(manager);
            }
        }
        free(ivars);
    }
}

static void fbt_FBMobileConfigDebug_viewDidLoad(id self, SEL _cmd) {
    FBTCaptureNativeUIManagers(self);
    FBTMobileConfigDebugWarmup();
    if (orig_FBMobileConfigDebug_viewDidLoad) {
        orig_FBMobileConfigDebug_viewDidLoad(self, _cmd);
    }
    UIViewController *controller = self;
    NSMutableArray *items = [controller.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    UIBarButtonItem *local = [[UIBarButtonItem alloc] initWithTitle:@"Mapa local" style:UIBarButtonItemStylePlain
        target:controller action:sel_registerName("fbt_openLocalConfigCatalog")];
    local.accessibilityIdentifier = @"fbtweak.mobileconfig.local";
    [items addObject:local];
    controller.navigationItem.rightBarButtonItems = items;
}

static void fbt_FBMobileConfigDebug_selectItem(id self, SEL selector, id item) {
    FBTCaptureNativeUIManagers(self);
    FBTMobileConfigQueryContext *context = [FBTMobileConfigQueryContext beginForOwner:self encodedSearchItem:item];
    // Item selections can fail on a background QE lookup before selectParam is
    // reached. Clear any older typed selection, but keep the original item flow.
    objc_setAssociatedObject(self, &kFBTMCSelectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FBTMobileConfigFetchDiagnosticsRecord(@"item_selection_started", @{
        @"config": context.configName ?: @"unknown", @"param": context.paramName ?: @""
    });
    if (orig_FBMobileConfigDebug_selectItem) orig_FBMobileConfigDebug_selectItem(self, selector, item);
}

static void fbt_FBMobileConfigDebug_selectParam(id self,
                                                 SEL _cmd,
                                                 const std::string &param,
                                                 int key,
                                                 const std::string &configName,
                                                 long long backendType,
                                                 NSString *backendName) {
    FBTCaptureNativeUIManagers(self);
    FBTMobileConfigDebugWarmup();
    [FBTMobileConfigQueryContext beginForOwner:self config:FBTStringFromStdString(configName) param:FBTStringFromStdString(param)];

    FBTMCSelection *selection = [[FBTMCSelection alloc] initWithParam:param
                                                                  key:key
                                                           configName:configName
                                                          backendType:backendType
                                                          backendName:backendName];
    objc_setAssociatedObject(self,
                             &kFBTMCSelectionKey,
                             selection,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    FBTLog(@"native MC select param=%@ config=%@ key=%d backendType=%lld backend=%@ contexts=%lu",
           FBTStringFromStdString(param),
           FBTStringFromStdString(configName),
           key,
           backendType,
           backendName ?: @"",
           (unsigned long)FBTNativeMobileConfigContextCount());
    FBTMobileConfigFetchDiagnosticsRecord(@"selection_started", @{
        @"param": FBTStringFromStdString(param),
        @"config": FBTStringFromStdString(configName),
        @"key": @(key),
        @"backend_type": @(backendType),
        @"backend": backendName ?: @"",
        @"context_count": @(FBTNativeMobileConfigContextCount())
    });

    // When the correct context manager has not been captured yet, defer the
    // first original invocation to the next short post-load window. The C++
    // arguments are owned by FBTMCSelection, so no borrowed pointer escapes.
    if ([FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled] &&
        FBTNativeMobileConfigContextCount() == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (objc_getAssociatedObject(self, &kFBTMCSelectionKey) != selection) return;
            FBTMobileConfigDebugWarmup();
            FBTCallOriginalSelection(self, _cmd, selection);
        });
        return;
    }

    FBTCallOriginalSelection(self, _cmd, selection);
}

static void fbt_FBMobileConfigDebug_present(id self,
                                             SEL _cmd,
                                             UIViewController *controller,
                                             BOOL animated,
                                             void (^completion)(void)) {
    if (FBTIsTransientParamInfoAlert(controller)) {
        FBTAddNamesDiagnosticsAction((UIAlertController *)controller);
        FBTMCSelection *selection = objc_getAssociatedObject(self, &kFBTMCSelectionKey);
        FBTMobileConfigQueryContext *queryContext = [FBTMobileConfigQueryContext contextForOwner:self];
        FBTMobileConfigFetchDiagnosticsRecord(@"qe_info_failure_alert", @{
            @"alert": ((UIAlertController *)controller).title ?: @"",
            @"alert_message": ((UIAlertController *)controller).message ?: @"",
            @"key": @(selection ? selection->_key : 0),
            @"param": queryContext.paramName ?: (selection ? FBTStringFromStdString(selection->_param) : @"unknown"),
            @"config": queryContext.configName ?: (selection ? FBTStringFromStdString(selection->_configName) : @"unknown"),
            @"retry": @(selection ? selection->_retryCount : 0),
            @"context_count": @(FBTNativeMobileConfigContextCount())
        });
        NSInteger httpStatus = FBTMobileConfigFetcherCaptureCurrentHTTPStatus();
        if (!httpStatus) httpStatus = queryContext.httpStatus;
        if (!httpStatus && selection) httpStatus = selection->_lastHTTPStatus;
        BOOL rejected = httpStatus == 400 || httpStatus == 401 || httpStatus == 403 ||
                        httpStatus == 404 || httpStatus == 410 || httpStatus == 422;
        if (rejected) {
            FBTMobileConfigFetchDiagnosticsRecord(@"qe_info_retry_skipped", @{
                @"http_status": @(httpStatus), @"capture_reason": @"selection_scoped_http_rejection"
            });
            UIAlertController *alert = (UIAlertController *)controller;
            NSString *explanation = [NSString stringWithFormat:@"O servidor recusou a consulta (HTTP %ld). Você pode editar os parâmetros no mapa local.", (long)httpStatus];
            alert.message = alert.message.length ? [alert.message stringByAppendingFormat:@"\n\n%@", explanation] : explanation;
        }
        BOOL warmupEnabled = [FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled];
        if (!rejected && warmupEnabled && selection && selection->_retryCount == 0 && orig_FBMobileConfigDebug_selectParam) {
            selection->_retryCount = 1;
            FBTLog(@"native MC transient param-info failure; retrying key=%d once", selection->_key);

            if (completion) completion();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (![FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled] ||
                    objc_getAssociatedObject(self, &kFBTMCSelectionKey) != selection) return;
                FBTMobileConfigDebugWarmup();
                SEL selectSel = sel_registerName("selectParam:key:configName:backendType:backendName:");
                FBTCallOriginalSelection(self, selectSel, selection);
            });
            return;
        }

        // Preserve the native failure and add a local path that does not
        // depend on the employee-only QE names/info endpoint.
        FBTAddLocalFallbackAction((UIAlertController *)controller, (UIViewController *)self);
    }

    if (orig_FBMobileConfigDebug_present) {
        orig_FBMobileConfigDebug_present(self, _cmd, controller, animated, completion);
    }
}

void FBTInstallMobileConfigDebugUIHooks(void) {
    BOOL warmupEnabled = [FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled];
    BOOL diagnosticsEnabled = [FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled];
    if (!warmupEnabled && !diagnosticsEnabled) return;
    FBTInstallForceNameActionHook();
    FBTMobileConfigResponseCaptureInstall();
    FBTInstallQEInfoFetchImportHook();
    FBTInstallQEInfoRefreshNamesImportHook();
    FBTInstallNamesAlertReporting();

    Class cls = objc_getClass("FBMobileConfigDebugViewController");
    if (!cls) return;

    @synchronized(cls) {
        class_addMethod(cls, sel_registerName("fbt_openLocalConfigCatalog"), (IMP)FBTOpenNativeLocalCatalog, "v@:");
        SEL viewDidLoadSel = sel_registerName("viewDidLoad");
        if (!orig_FBMobileConfigDebug_viewDidLoad &&
            FBTMCUIEncodingEquals(cls, viewDidLoadSel, "v16@0:8")) {
            MSHookMessageEx(cls,
                            viewDidLoadSel,
                            (IMP)fbt_FBMobileConfigDebug_viewDidLoad,
                            (IMP *)&orig_FBMobileConfigDebug_viewDidLoad);
        }

        SEL itemSel = sel_registerName("selectMobileConfigItem:");
        if (!orig_FBMobileConfigDebug_selectItem && FBTMCUIEncodingEquals(cls, itemSel, "v24@0:8@16")) {
            MSHookMessageEx(cls, itemSel, (IMP)fbt_FBMobileConfigDebug_selectItem, (IMP *)&orig_FBMobileConfigDebug_selectItem);
        }

        SEL selectSel = sel_registerName("selectParam:key:configName:backendType:backendName:");
        if (!orig_FBMobileConfigDebug_selectParam &&
            FBTMCUIEncodingEquals(cls, selectSel, "v52@0:8r^v16i24r^v28q36@44")) {
            MSHookMessageEx(cls,
                            selectSel,
                            (IMP)fbt_FBMobileConfigDebug_selectParam,
                            (IMP *)&orig_FBMobileConfigDebug_selectParam);
        }

        SEL presentSel = @selector(presentViewController:animated:completion:);
        Method presentMethod = class_getInstanceMethod(cls, presentSel);
        if (presentMethod && method_getNumberOfArguments(presentMethod) == 5 &&
            !orig_FBMobileConfigDebug_present) {
            MSHookMessageEx(cls,
                            presentSel,
                            (IMP)fbt_FBMobileConfigDebug_present,
                            (IMP *)&orig_FBMobileConfigDebug_present);
        }
    }
}

void FBTInstallMobileConfigDebugUIBootstrap(void) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled] &&
        ![FBTDefaults boolForKey:FBTKeyMobileConfigFetchDiagnosticsEnabled]) return;

    FBTInstallMobileConfigDebugUIHooks();
    if (sBundleObserverInstalled) return;
    sBundleObserverInstalled = YES;

    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSBundleDidLoadNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        NSBundle *bundle = [note.object isKindOfClass:[NSBundle class]] ? note.object : nil;
        NSString *last = bundle.bundlePath.lastPathComponent ?: @"";
        if ([last containsString:@"FBRarelyUsedFramework"] ||
            [last containsString:@"FBReactNativeProductsFramework"] ||
            [last containsString:@"FBSharedDynamicFramework"]) {
            // Context/readers may only become visible after these images load.
            // The installer rescans when the Objective-C class count changes;
            // its per-method sets prevent duplicate hooks.
            FBTInstallNativeMobileConfigContextCapture();
            FBTInstallMobileConfigDebugUIHooks();
        }
    }];
}

NSDictionary *FBTMobileConfigDebugUIHookStatus(void) {
    NSDictionary *contexts;
    @synchronized([FBTMCSelection class]) { contexts = [sLatestNativeUIContexts copy] ?: @{}; }
    return @{@"native_names_alert_reporting_available": @(sOriginalNamesAlertFactory != NULL), @"qe_info_hook_available": @(orig_FBMobileConfigQEInfoFetch != NULL),
        @"force_name_action_hook_available": @(sOriginalForceNameAction != NULL),
        @"force_name_action_hook_failure": sForceNameActionFailure ?: @"not_attempted",
        @"name_download_hook_available": @(orig_FBMobileConfigQEInfoRefreshNames != NULL),
        @"selection_hook_available": @(orig_FBMobileConfigDebug_selectParam != NULL),
        @"item_selection_hook_available": @(orig_FBMobileConfigDebug_selectItem != NULL),
        @"error_metadata_hook_available": @(orig_NSError_initWithDomain != NULL),
        @"contexts": contexts};
}

