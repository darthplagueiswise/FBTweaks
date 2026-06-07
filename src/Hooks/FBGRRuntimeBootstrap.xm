#import <Foundation/Foundation.h>
#import "../Runtime/FBGRBoolRuntimeInventory.h"
#import "../Runtime/FBGRGateStore.h"

extern void FBGRMCGateHooksApplyPersistedOverrides(void);

__attribute__((constructor)) static void FBGRRuntimeBootstrap(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [FBGRBoolRuntimeInventory installPersistedOverrideHooks];
            if (FBGRGateAllOverrideSlotIds().count > 0) FBGRMCGateHooksApplyPersistedOverrides();
        });
    }
}
