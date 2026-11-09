#ifndef FBT_NATIVE_INTERNAL_MENUS_H
#define FBT_NATIVE_INTERNAL_MENUS_H
#import <UIKit/UIKit.h>

// Launches exact native Facebook 567 controllers (FBRarelyUsed/FBShared).
// No search redirect, guessed MobileConfig contexts, or synthetic UI.
FOUNDATION_EXPORT BOOL FBTNativeOpenController(NSString *identifier, NSString **failure);

// Opens the existing native Bug Report / Dogfooding Assistant coordinator.
FOUNDATION_EXPORT BOOL FBTNativeOpenDogfoodingAssistant(NSString **failure);

// Executes the genuine Employee Settings user-option with the real
// session, tab and navigation coordinator, if all are exposed.
FOUNDATION_EXPORT BOOL FBTNativeOpenEmployeeUserOption(NSString **failure);
#endif
