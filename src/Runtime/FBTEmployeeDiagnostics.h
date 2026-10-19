#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
// Values observed at client getters. No account IDs, objects or tokens retained.
void FBTEmployeeObserveBool(NSString *source, BOOL original, BOOL effective, const void *caller);
void FBTEmployeeObserveMCBool(uint64_t key, BOOL original, BOOL effective, const void *caller);
// Temporary local experiment for exactly tw_is_employee.enabled, not all tw_*.
void FBTEmployeeArmTWProbe(void);
void FBTEmployeeCancelTWProbe(void);
BOOL FBTEmployeeApplyTWProbe(uint64_t key, BOOL value);
NSDictionary *FBTEmployeeDiagnosticsSnapshot(void);
void FBTEmployeeDiagnosticsReset(void);
#ifdef __cplusplus
}
#endif
