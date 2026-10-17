#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif

// Bounded in-process decoding; never accepts a formatted native error as HTTP JSON.
NSData *FBTNamesDecodeResponse(NSData *data, NSString **status);
NSDictionary *FBTNamesResponseSummary(NSData *data);
NSString *FBTNamesRedactMessage(NSString *message);
#ifdef __cplusplus
}
#endif
