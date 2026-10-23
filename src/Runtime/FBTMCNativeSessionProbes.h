#ifndef FBT_MC_NATIVE_SESSION_PROBES_H
#define FBT_MC_NATIVE_SESSION_PROBES_H

#import <Foundation/Foundation.h>

// Toggle-only, ephemeral session probes. Never stored in NSUserDefaults.
// Installing a verified data callback may not be reversible at runtime;
// turning OFF makes its installed wrapper forward the original unchanged.
FOUNDATION_EXPORT NSString * const FBTMCNativeProbeTigonKey;
FOUNDATION_EXPORT NSString * const FBTMCNativeProbeFetcherKey;
BOOL FBTMCNativeProbeIsKey(NSString *key);
BOOL FBTMCNativeProbeIsEnabled(NSString *key);
BOOL FBTMCNativeProbeAnyEnabled(void);
// Stop observation when the parent QE-info diagnostic switch is disabled.
// Existing verified data-slot wrappers remain forwarding-only until process exit.
void FBTMCNativeProbeDisableAll(void);
BOOL FBTMCNativeProbeSetEnabled(NSString *key, BOOL enabled, NSString **reason);
NSDictionary *FBTMCNativeProbeStatus(void);
#endif
