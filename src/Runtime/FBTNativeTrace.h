#ifndef FBT_NATIVE_TRACE_H
#define FBT_NATIVE_TRACE_H
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
void FBTNativeTraceReloadPrefs(void);
BOOL FBTNativeTraceIsEnabled(void);
void FBTNativeTraceRecordBool(NSString *methodKey, int original, int effective);
void FBTNativeTraceRecordNetwork(NSString *event, NSDictionary *safeDetails);
NSDictionary *FBTNativeTraceSnapshot(void);
void FBTNativeTraceClear(void);
#ifdef __cplusplus
}
#endif
#endif
