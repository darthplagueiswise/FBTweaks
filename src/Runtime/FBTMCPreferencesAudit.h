#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Compares the resolved native mc_overrides.json against the active-bundle Preferences plist.
// The report distinguishes persisted-value mismatches from parameters absent from the plist.
NSDictionary *FBTMCPreferencesAuditRun(void);

#ifdef __cplusplus
}
#endif
