#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif

// Bounded in-process decoding; never accepts a formatted native error as HTTP JSON.
NSData *FBTNamesDecodeResponse(NSData *data, NSString **status);
NSDictionary *FBTNamesResponseSummary(NSData *data);
NSString *FBTNamesRedactMessage(NSString *message);
// Evidence-based UI classification. Code 100 alone is not an employee error.
NSDictionary *FBTNamesDiagnosticAdvice(NSDictionary *event);
#ifdef __cplusplus
}
#endif


#ifdef __cplusplus
extern "C" {
#endif
// Observations only: never changes the native request, callback or overrides.
NSDictionary *FBTNamesAssessRequest(NSDictionary *request, NSDictionary *response, NSDictionary *completion);
NSArray<NSDictionary *> *FBTNamesAssessHistory(NSArray<NSDictionary *> *events, NSString *processSessionID);
#ifdef __cplusplus
}
#endif
