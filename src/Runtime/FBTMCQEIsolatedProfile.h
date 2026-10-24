#ifndef FBT_MC_QE_ISOLATED_PROFILE_H
#define FBT_MC_QE_ISOLATED_PROFILE_H
#import <Foundation/Foundation.h>

// Independent compile-time gate, never FBT_ENABLE_QE_INVASIVE_HOOKS.
// The production build is read-only; LAB must be explicitly built and armed.
#ifndef FBT_ENABLE_QE_ISOLATED_PROFILE
#define FBT_ENABLE_QE_ISOLATED_PROFILE 0
#endif

#ifdef __cplusplus
extern "C" {
#endif
BOOL FBTMCQEIsolatedProfileAvailable(void);
BOOL FBTMCQEIsolatedProfileInstalled(void);
BOOL FBTMCQEIsolatedProfileArm(NSString **reason);
void FBTMCQEIsolatedProfileCancel(void);
NSDictionary *FBTMCQEIsolatedProfileStatus(void);
#ifdef __cplusplus
}
#endif
#endif
