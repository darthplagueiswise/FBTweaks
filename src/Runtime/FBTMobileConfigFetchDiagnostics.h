#ifndef FBT_MOBILECONFIG_FETCH_DIAGNOSTICS_H
#define FBT_MOBILECONFIG_FETCH_DIAGNOSTICS_H
#import <Foundation/Foundation.h>

// The legacy QE transport capture rewrites C++/vtable pointers and globally
// hooks NSURLSession/NSError. Those ABI-sensitive paths are quarantined in
// sideloaded release builds. The native UI QE events remain available.
// A dedicated ABI-validated LAB build may explicitly opt in; never infer
// compatibility from a successful Theos compilation or a matching UUID.
#ifndef FBT_ENABLE_QE_INVASIVE_HOOKS
#define FBT_ENABLE_QE_INVASIVE_HOOKS 0
#endif
static inline BOOL FBTQEInvasiveHooksAllowed(void) {
    return FBT_ENABLE_QE_INVASIVE_HOOKS == 1;
}

#ifdef __cplusplus
extern "C" {
#endif
void FBTMobileConfigFetchDiagnosticsReset(void);
void FBTMobileConfigFetchDiagnosticsRecord(NSString *event, NSDictionary *details);
NSDictionary *FBTMobileConfigFetchDiagnosticsSnapshot(void);
NSString *FBTMobileConfigFetchDiagnosticsJSON(void);
#ifdef __cplusplus
}
#endif

#endif /* FBT_MOBILECONFIG_FETCH_DIAGNOSTICS_H */

