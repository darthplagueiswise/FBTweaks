#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import "FBTMobileConfigRuntime.h"
#import "FBTNativeMobileConfigOverrides.h"
#import "FBTMobileConfigDebugUIHooks.h"
#import <objc/runtime.h>
#import <string.h>
#include <string>

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

static FBTViewDidLoadOrig orig_FBMobileConfigDebug_viewDidLoad = NULL;
static FBTSelectParamOrig orig_FBMobileConfigDebug_selectParam = NULL;
static FBTPresentViewControllerOrig orig_FBMobileConfigDebug_present = NULL;
static BOOL sBundleObserverInstalled = NO;
static char kFBTMCSelectionKey;

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

static BOOL FBTMCUIEncodingEquals(Class cls, SEL sel, const char *expected) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    return actual && expected && strcmp(actual, expected) == 0;
}

static void FBTMobileConfigDebugWarmup(void) {
    // Post-launch/user-triggered only. Installing the fishhooks is safe here;
    // capture/override behavior remains controlled by live preferences.
    FBTInstallMobileConfigRuntime();
    FBTInstallNativeMobileConfigContextCapture();
    FBTMobileConfigReloadPrefs();
}

static void FBTCallOriginalSelection(id controller, SEL selector, FBTMCSelection *selection) {
    if (!controller || !selection || !orig_FBMobileConfigDebug_selectParam) return;
    orig_FBMobileConfigDebug_selectParam(controller,
                                         selector,
                                         selection->_param,
                                         selection->_key,
                                         selection->_configName,
                                         selection->_backendType,
                                         selection->_backendName);
}

static void FBTOpenLocalMobileConfigFallback(UIViewController *presenter) {
    FBTMobileConfigViewController *local =
        [[FBTMobileConfigViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
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

static void fbt_FBMobileConfigDebug_viewDidLoad(id self, SEL _cmd) {
    FBTMobileConfigDebugWarmup();
    if (orig_FBMobileConfigDebug_viewDidLoad) {
        orig_FBMobileConfigDebug_viewDidLoad(self, _cmd);
    }
}

static void fbt_FBMobileConfigDebug_selectParam(id self,
                                                 SEL _cmd,
                                                 const std::string &param,
                                                 int key,
                                                 const std::string &configName,
                                                 long long backendType,
                                                 NSString *backendName) {
    FBTMobileConfigDebugWarmup();

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

    // When the correct context manager has not been captured yet, defer the
    // first original invocation to the next short post-load window. The C++
    // arguments are owned by FBTMCSelection, so no borrowed pointer escapes.
    if (FBTNativeMobileConfigContextCount() == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
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
        FBTMCSelection *selection = objc_getAssociatedObject(self, &kFBTMCSelectionKey);
        if (selection && selection->_retryCount == 0 && orig_FBMobileConfigDebug_selectParam) {
            selection->_retryCount = 1;
            FBTLog(@"native MC transient param-info failure; retrying key=%d once", selection->_key);

            if (completion) completion();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                FBTMobileConfigDebugWarmup();
                SEL selectSel = sel_registerName("selectParam:key:configName:backendType:backendName:");
                FBTCallOriginalSelection(self, selectSel, selection);
            });
            return;
        }

        // Preserve the native second failure and add a local path that does not
        // depend on the employee-only QE names/info endpoint.
        FBTAddLocalFallbackAction((UIAlertController *)controller,
                                  (UIViewController *)self);
    }

    if (orig_FBMobileConfigDebug_present) {
        orig_FBMobileConfigDebug_present(self, _cmd, controller, animated, completion);
    }
}

void FBTInstallMobileConfigDebugUIHooks(void) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) return;

    Class cls = objc_getClass("FBMobileConfigDebugViewController");
    if (!cls) return;

    @synchronized(cls) {
        SEL viewDidLoadSel = sel_registerName("viewDidLoad");
        if (!orig_FBMobileConfigDebug_viewDidLoad &&
            FBTMCUIEncodingEquals(cls, viewDidLoadSel, "v16@0:8")) {
            MSHookMessageEx(cls,
                            viewDidLoadSel,
                            (IMP)fbt_FBMobileConfigDebug_viewDidLoad,
                            (IMP *)&orig_FBMobileConfigDebug_viewDidLoad);
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
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) return;

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
            FBTInstallMobileConfigDebugUIHooks();
        }
    }];
}
