#import <Foundation/Foundation.h>

// Thread-local: excludes only this inspection from the tweak's override hooks.
BOOL FBTMobileConfigIsInspectingSystemValue(void);
NSDictionary *FBTMobileConfigInspectParameter(NSDictionary *configuration, NSDictionary *parameter);
NSString *FBTMobileConfigValueText(id value, NSString *type);
