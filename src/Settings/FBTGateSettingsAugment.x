// Explicit gate-family actions invoked by the new grouped Settings UI.
//
// Previously this translation unit installed a Logos hook on
// FBTSettingsViewController from its own %ctor. That caused ObjC calls while
// dyld4 was still running initializers, and its five-section mutation logic
// no longer matched the modern six-group menu. Do not reintroduce a %ctor,
// %hook, or UI replacement here.
#import "FBTPrefix.h"
#import "FBTDefaults.h"
#import "Runtime/FBTRuntimeBoolBrowser.h"
#import "Runtime/FBTMobileConfigDebugUIHooks.h"
#import "Features/Employee/FBTInternalImports.h"
#import "Features/ReactNative/FBTReactNativeInternal.h"

extern void FBTInitEmployeeGroup(void);
extern void FBTInstallKnownGateRuntimeHooks(void);

void FBTSettingsGateDidSwitch(NSString *key, BOOL enabled) {
    if (!key.length) return;

    if ([key isEqualToString:FBTKeyEmployeeEnabled] ||
        [key isEqualToString:FBTKeyTestUserEnabled] ||
        [key isEqualToString:FBTKeyKnownDogfoodEnabled]) {
        if (enabled) FBTInitEmployeeGroup();
        FBTInstallKnownGateRuntimeHooks();
        FBTInternalImportReloadPrefs();

        if ([FBTDefaults boolForKey:FBTKeyEmployeeEnabled] ||
            [FBTDefaults boolForKey:FBTKeyTestUserEnabled]) {
            FBTInstallInternalImportHooks();
            FBTInitReactNativeInternalGroup();
            FBTInstallReactNativeAndBuildImportHooks();
        }
    }

    if (([key isEqualToString:FBTKeyReactNativeInternalEnabled] ||
         [key isEqualToString:FBTKeyBetaBuildEnabled]) && enabled) {
        FBTInitReactNativeInternalGroup();
        FBTInstallReactNativeAndBuildImportHooks();
    }

    if ([key isEqualToString:FBTKeyMobileConfigNativeUIWarmupEnabled] && enabled) {
        FBTInstallMobileConfigDebugUIBootstrap();
        FBTInstallMobileConfigDebugUIHooks();
    }

    if ([key isEqualToString:FBTKeyDogfoodSweepEnabled] && !enabled) {
        FBTRuntimeBoolClearSweep(@"dogfood");
    } else if ([key isEqualToString:FBTKeyInternalDebugSweepEnabled] && !enabled) {
        FBTRuntimeBoolClearSweep(@"internaldebug");
    }
}
