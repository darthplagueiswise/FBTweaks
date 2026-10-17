#ifndef FBT_MOBILECONFIG_RESPONSE_CAPTURE_H
#define FBT_MOBILECONFIG_RESPONSE_CAPTURE_H
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opt-in, post-launch response-body capture for QE-info/name-download diagnostics.
// Request headers, authorization values and request bodies are never persisted.
void FBTMobileConfigResponseCaptureInstall(void);
void FBTMobileConfigResponseCaptureInstallTigon(void);
void FBTMobileConfigFetcherCaptureInstall(void);
NSDictionary *FBTMobileConfigFetcherCaptureStatus(void);
// Selection-scoped correlation: begin/end on the same thread, in LIFO order.
// Async callbacks own shared state, so a late response cannot touch a dead scope.
void *FBTMobileConfigFetcherCaptureBeginScope(void);
NSInteger FBTMobileConfigFetcherCaptureCurrentHTTPStatus(void);
NSInteger FBTMobileConfigFetcherCaptureEndScope(void *scope);

NSDictionary *FBTMobileConfigTigonCaptureStatus(void);
// Called only from the UUID-verified native MC completion. No onStarted required.
NSDictionary *FBTMobileConfigTigonCaptureObserveNativeCompletion(NSDictionary *request, BOOL success);
NSDictionary *FBTMobileConfigResponseCaptureArmInfo(void);
BOOL FBTMobileConfigResponseCaptureShouldCaptureRequest(NSString *host, NSString *path, NSString *reason);
void FBTMobileConfigResponseCaptureWriteRawBody(NSData *data, NSString *host, NSString *path,
    NSString *method, NSDictionary *queryHashState, NSString *reason, NSInteger httpStatus,
    NSString *contentType, NSString *transport);
void FBTMobileConfigResponseCaptureRecordTransportEvent(NSString *event, NSDictionary *details);
void FBTMobileConfigResponseCaptureArm(NSString *reason);
NSString *FBTMobileConfigResponseCaptureLastBodyString(void);
NSDictionary *FBTMobileConfigResponseCaptureStatus(void);

#ifdef __cplusplus
}
#endif
#endif
