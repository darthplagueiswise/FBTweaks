#import <Foundation/Foundation.h>

// Thread-local: excludes only this inspection from the tweak's override hooks.
BOOL FBTMobileConfigIsInspectingSystemValue(void);
// All synthetic inspection reads, including the read with tweak forcing.
BOOL FBTMobileConfigIsInspectingValue(void);
BOOL FBTMobileConfigShouldBypassTweakOverrides(void);
NSDictionary *FBTMobileConfigInspectParameter(NSDictionary *configuration, NSDictionary *parameter);
// Explicit action: force reload in the uniquely selected native context, then
// read back. reload_returned does not certify parsing or import success.
NSDictionary *FBTMobileConfigReloadAndInspectParameter(NSDictionary *configuration, NSDictionary *parameter);
NSString *FBTMobileConfigValueText(id value, NSString *type);
