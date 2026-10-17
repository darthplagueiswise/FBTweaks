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
NSDictionary *FBTMobileConfigTigonCaptureStatus(void);
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
