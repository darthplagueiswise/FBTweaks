#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import "FBTMobileConfigRuntime.h"
#import "FBTNativeMobileConfigOverrides.h"
#import "FBTMobileConfigDebugUIHooks.h"
#import <objc/runtime.h>
#import <string.h>

// The advanced native MobileConfig UI now lives in FBRarelyUsedFramework and
// may enter after the tweak constructor. These hooks do not suppress the
// native fetch error and do not fabricate QE metadata. They ensure the local
// reader/context hooks are installed when the native controller is actually
// alive, before it resolves a selected parameter.

typedef void (*FBTViewDidLoadOrig)(id, SEL);
typedef void (*FBTSelectParamOrig)(id, SEL, const void *, int, const void *, long long, id);

static FBTViewDidLoadOrig orig_FBMobileConfigDebug_viewDidLoad = NULL;
static FBTSelectParamOrig orig_FBMobileConfigDebug_selectParam = NULL;
static BOOL sBundleObserverInstalled = NO;

static BOOL FBTMCUIEncodingEquals(Class cls, SEL sel, const char *expected) {
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    return actual && expected && strcmp(actual, expected) == 0;
}

static void FBTMobileConfigDebugWarmup(void) {
    if ([FBTDefaults boolForKey:FBTKeyMobileConfigRuntimeEnabled]) {
        FBTInstallMobileConfigRuntime();
    }
    FBTInstallNativeMobileConfigContextCapture();
    FBTMobileConfigReloadPrefs();
}

static void fbt_FBMobileConfigDebug_viewDidLoad(id self, SEL _cmd) {
    FBTMobileConfigDebugWarmup();
    if (orig_FBMobileConfigDebug_viewDidLoad) {
        orig_FBMobileConfigDebug_viewDidLoad(self, _cmd);
    }
}

static void fbt_FBMobileConfigDebug_selectParam(id self,
                                                 SEL _cmd,
                                                 const void *param,
                                                 int key,
                                                 const void *configName,
                                                 long long backendType,
                                                 id backendName) {
    FBTMobileConfigDebugWarmup();
    if (orig_FBMobileConfigDebug_selectParam) {
        orig_FBMobileConfigDebug_selectParam(self, _cmd, param, key,
                                             configName, backendType, backendName);
    }
}

void FBTInstallMobileConfigDebugUIHooks(void) {
    if (![FBTDefaults boolForKey:FBTKeyMobileConfigNativeUIWarmupEnabled]) return;

    Class cls = objc_getClass("FBMobileConfigDebugViewController");
    if (!cls) return;

    SEL viewDidLoadSel = sel_registerName("viewDidLoad");
    if (!orig_FBMobileConfigDebug_viewDidLoad &&
        FBTMCUIEncodingEquals(cls, viewDidLoadSel, "v16@0:8")) {
        MSHookMessageEx(cls, viewDidLoadSel,
                        (IMP)fbt_FBMobileConfigDebug_viewDidLoad,
                        (IMP *)&orig_FBMobileConfigDebug_viewDidLoad);
    }

    SEL selectSel = sel_registerName("selectParam:key:configName:backendType:backendName:");
    if (!orig_FBMobileConfigDebug_selectParam &&
        FBTMCUIEncodingEquals(cls, selectSel, "v52@0:8r^v16i24r^v28q36@44")) {
        MSHookMessageEx(cls, selectSel,
                        (IMP)fbt_FBMobileConfigDebug_selectParam,
                        (IMP *)&orig_FBMobileConfigDebug_selectParam);
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
