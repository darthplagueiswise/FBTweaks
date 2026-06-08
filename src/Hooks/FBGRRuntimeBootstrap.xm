#import <Foundation/Foundation.h>
#import "../Runtime/FBGRBoolRuntimeInventory.h"
#import "../Runtime/FBGRGateStore.h"
#import "FBGRHookExports.h"

static void FBGRRuntimeApplyPersistedOverridesPass(void) {
    [FBGRBoolRuntimeInventory installPersistedOverrideHooks];

    if (FBGRGateAllOverrideSlotIds().count > 0) {
        FBGRMCGateHooksApplyPersistedOverrides();
    }
}

static void FBGRRuntimeSchedulePersistedPass(NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        FBGRRuntimeApplyPersistedOverridesPass();
    });
}

__attribute__((constructor)) static void FBGRRuntimeBootstrap(void) {
    @autoreleasepool {
        FBGRGateWarmCacheFromPrefs();

        FBGRRuntimeSchedulePersistedPass(0.15);
        FBGRRuntimeSchedulePersistedPass(1.0);
        FBGRRuntimeSchedulePersistedPass(2.5);
        FBGRRuntimeSchedulePersistedPass(5.0);
        FBGRRuntimeSchedulePersistedPass(10.0);
    }
}
