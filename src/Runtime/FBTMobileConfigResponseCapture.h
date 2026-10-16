#ifndef FBT_MOBILECONFIG_RESPONSE_CAPTURE_H
#define FBT_MOBILECONFIG_RESPONSE_CAPTURE_H
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opt-in, post-launch response-body capture for QE-info/name-download diagnostics.
// Request headers, authorization values and request bodies are never persisted.
void FBTMobileConfigResponseCaptureInstall(void);
void FBTMobileConfigResponseCaptureArm(NSString *reason);
NSString *FBTMobileConfigResponseCaptureLastBodyString(void);
NSDictionary *FBTMobileConfigResponseCaptureStatus(void);

#ifdef __cplusplus
}
#endif
#endif
