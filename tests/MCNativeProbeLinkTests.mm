#import <Foundation/Foundation.h>
#import "../src/Runtime/FBTMCNativeSessionProbes.h"

// This TU is compiled as Objective-C++, while the probe controller is
// compiled as Objective-C. Link both into one executable to test the ABI.
extern "C" BOOL FBTMCNativeProbeCrossLanguageLinkTest(void) {
    return FBTMCNativeProbeIsKey(FBTMCNativeProbeTigonKey) &&
        !FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey) &&
        !FBTMCNativeProbeAnyEnabled();
}
