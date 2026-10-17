#ifndef FBT_MOBILECONFIG_FETCH_DIAGNOSTICS_H
#define FBT_MOBILECONFIG_FETCH_DIAGNOSTICS_H
#import <Foundation/Foundation.h>

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

