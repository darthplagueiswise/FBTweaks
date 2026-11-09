#ifndef FBT_NATIVE_INTERNAL_SURFACES_H
#define FBT_NATIVE_INTERNAL_SURFACES_H

#import <UIKit/UIKit.h>

// Uses the *live* React Native bridge and its RCTDevMenu module.
// No fabricated RCTBridge, class scan, or MobileConfig overrides.
FOUNDATION_EXPORT BOOL FBTNativeShowReactDevMenu(UIViewController *presenter, NSString **error);

// Read-only diagnostics for the Facebook 567 internal surfaces.
// Class presence alone does not prove a usable feature or remote eligibility.
FOUNDATION_EXPORT NSString *FBTNativeInternalSurfacesReport(void);

#endif
