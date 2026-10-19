#ifndef FBT_NATIVE_TRACE_H
#define FBT_NATIVE_TRACE_H
#import <Foundation/Foundation.h>
void FBTNativeTraceReloadPrefs(void);
BOOL FBTNativeTraceIsEnabled(void);
void FBTNativeTraceRecordBool(NSString *methodKey, int original, int effective);
void FBTNativeTraceRecordNetwork(NSString *event, NSDictionary *safeDetails);
NSDictionary *FBTNativeTraceSnapshot(void);
void FBTNativeTraceClear(void);
#endif
