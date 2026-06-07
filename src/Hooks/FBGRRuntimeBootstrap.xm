#import <Foundation/Foundation.h>
#import "../Runtime/FBGRBoolRuntimeInventory.h"
#import "../Runtime/FBGRGateStore.h"

// Startup stays intentionally light. No ObjC image scan, no MobileConfig hook pass,
// no persisted runtime hook replay in constructor. Runtime hooks are installed when
// the user toggles a concrete row or explicitly reloads MC hooks from the menu.
extern "C" void FBGRRuntimeBootstrapNoop(void) {}
