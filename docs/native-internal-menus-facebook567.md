# Facebook iOS 567 — Native internal menu entrypoints

Source: **the decrypted Facebook 567.0.0 IPA** (CFBundleVersion 1003138444), ObjC class/method metadata extracted from its actual Mach-O images.

This document describes code that was verified statically. **It does not claim runtime or server authorization on a device.**

## Direct UIViewController initializers

| Entry | Image | Objective-C initializer encoding | Mechanism |
|---|---|---|---|
| FFDB Internal Settings | FBRarelyUsedFramework | No class-specific initializer, inherited `init` | Allocate original UIViewController |
| About Internal Settings | FBRarelyUsedFramework | `initWithSession:` `@24@0:8@16` | Original FBUserSession |
| React OTA Internal Settings | FBRarelyUsedFramework | `initWithSession:` `@24@0:8@16` | Original FBUserSession |
| Download on Demand | FBRarelyUsedFramework | `initWithSession:` `@24@0:8@16` | Original FBUserSession |
| Logged Out Push | FBRarelyUsedFramework | `initWithSession:` `@24@0:8@16` | Original FBUserSession |
| Reliable Media | FBRarelyUsedFramework | `initWithSession:` `@24@0:8@16` | Original FBUserSession |
| Clash Management | FBSharedFramework | `initWithSession:` `@24@0:8@16` | Original FBUserSession |
| Lifecycle Internal Settings | FBRarelyUsedFramework | No class-specific initializer | Original UIViewController |
| Autofill Tokenization (Swift) | FBRarelyUsedFramework | `initWithStyle:` `@24@0:8q16` | Original UITableViewController |
| Messaging Thread View (Swift) | FBCameraFramework | `initWithStyle:` `@24@0:8q16` | Original UITableViewController |

Implementation: `src/Runtime/FBTNativeInternalMenus.m`. Every native class is looked up only after the user taps the action. The initializer's argument count and ABI are checked before calling. The resulting instance must actually be a UIViewController. No template screen replaces the native controller.

## Context-dependent native entrypoints

- **MobileConfig Debug:** `FBMobileConfigDebugViewController` exists in FBRarelyUsedFramework; it expects `initWithFBMobileConfigContextManagers:resetAppCallback:` with `{_FBMobileConfigContextManagers=@@@@@@}` (six native context-manager object fields). The tweak does **not** construct that structure using nils or guesses. Instead it asks the native Internal Settings provider to **select the MobileConfig plugin's actual UITableView row**, dispatching the original delegate action. No UI search bar is used. If that provider does not register a row, the button returns an explicit failure.
- **Employee Settings:** `FBEmployeeSettingsUserOption` in FBSharedFramework has `initWithSession:tabID:navigationCoordinator:` (`@40@0:8@16@24@32`), then `performUserOptionAction` (`v16@0:8`). The tweak uses that native action only if it can obtain all three genuine objects and validates method types. **This is an option, not an independent UIViewController.**
- **Dogfooding Assistant:** `FBBugReportInitialCoordinator` in FBSharedFramework exposes `openBugReportForm` (`v16@0:8`) and `triageToDogfoodingAssistantSession` (`B16@0:8`). The button calls the **existing, live coordinator** if found, rather than constructing a bug-reporter model with invalid dependencies. If the coordinator is not discoverable, it reports that exact limitation. The Assistant is part of the native bug-report/triage workflow, not a verified stand-alone root menu.
- **React Native Internal Settings:** original `fb://rninternalsettings` route in FBReactNativeProductsFramework.
- **React Native Dev Menu:** original `RCTDevMenu.show` method on an existing bridge module.
- **Native Internal Settings:** exported `FBInternalSettingsViewControllerFromSession(session)` from FBSharedFramework.
- **Whitehat:** existing original controller from FBRarelyUsedFramework.
- **DogFood/Gold:** native Swift `FBDogFoodUI.DogFoodController.getNagSheetWithSession:...` is the **sheet factory only**. It accepts caller-provided `onSwitch` and `onSnooze` callbacks; it is not proof of an official Gold/MDM enrollment. The current toggle writes local `FBDogFood-managedPhoneFlag`, separately from Employee; official Gold activation is **not implemented**.

## Safety and runtime validation

- Work is deferred until after dyld's initializer stack. No new pre-main constructors or Logos hooks added.
- Unknown/private native initializers are **not** called.
- Known controllers may still have runtime dependencies not visible in ObjC metadata. The compiled IPA on iOS 27 needs device-side UI tests, and on-device errors are recorded instead of reporting success prematurely.
- A successful local Employee getter or managed-phone preference does not establish remote authorization.
- The original server identity, OAuth credentials, signing, and entitlement state are not changed by these navigation actions.
