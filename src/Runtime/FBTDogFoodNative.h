#ifndef FBT_DOGFOOD_NATIVE_H
#define FBT_DOGFOOD_NATIVE_H

#import <UIKit/UIKit.h>

// Opens the genuine Facebook 567 Swift DogFoodUI sheet with the active FBUserSession.
// No MobileConfig slot overrides, global NSUserDefaults hooks or server requests.
// Returns NO with a diagnostic when the native class/ABI/session is unavailable.
FOUNDATION_EXPORT BOOL FBTDogFoodPresentNativeNag(UIViewController *presenter, NSString **error);

// The local flag that Facebook 567 reads. This is NOT Gold/MDM enrollment.
FOUNDATION_EXPORT BOOL FBTDogFoodManagedPhoneFlag(void);
FOUNDATION_EXPORT void FBTDogFoodSetManagedPhoneFlag(BOOL enabled);

#endif /* FBT_DOGFOOD_NATIVE_H */
