#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
// Process memory only. Does not send requests or change credentials/results.
NSDictionary *FBTQERequestOptionsSnapshot(void);
void FBTQERequestOptionsSetEnabled(BOOL enabled);
void FBTQERequestOptionsSetAllQE(BOOL allQE);
BOOL FBTQERequestOptionsSetValue(NSString *key, BOOL value);
void FBTQERequestOptionsReset(BOOL completeProfile);
#ifdef __cplusplus
}
#endif
