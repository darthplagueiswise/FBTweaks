#ifndef FBT_NETWORK_INSPECTOR_STORE_H
#define FBT_NETWORK_INSPECTOR_STORE_H
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
// Local, opt-in, session-only capture; records stay inside app's protected sandbox.
BOOL FBTNetworkInspectorIsCapturing(void);
void FBTNetworkInspectorSetCapturing(BOOL enabled);
void FBTNetworkInspectorRecordRequest(NSDictionary *request, NSArray<NSDictionary *> *pairs);
void FBTNetworkInspectorRecordTigon(NSDictionary *context, NSData *body);
void FBTNetworkInspectorRecordCompletion(NSDictionary *completion, NSData *body);
NSArray<NSDictionary *> *FBTNetworkInspectorSummaries(void);
NSDictionary *FBTNetworkInspectorRecordWithID(NSString *recordID);
NSArray<NSURL *> *FBTNetworkInspectorExportURLs(void);
void FBTNetworkInspectorClear(void);
NSDictionary *FBTNetworkInspectorStatus(void);
#ifdef __cplusplus
}
#endif
#endif
