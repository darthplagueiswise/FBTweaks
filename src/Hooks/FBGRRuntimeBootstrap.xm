#import <Foundation/Foundation.h>
#import "../Runtime/FBGRBoolRuntimeInventory.h"
#import "../Runtime/FBGRGateStore.h"

extern "C" void FBGRMCGateHooksApplyPersistedOverrides(void);

%ctor {
    @autoreleasepool {
        [FBGRBoolRuntimeInventory installPersistedOverrideHooks];
        if (FBGRGateAllOverrideSlotIds().count > 0) {
            FBGRMCGateHooksApplyPersistedOverrides();
        }
    }
}
