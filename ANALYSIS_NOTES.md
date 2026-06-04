# FBTweaks v0.3.4 notes

Base used: `FBTweaks-a2e50cf807837a142450477e1da79e34e45d4fdf.zip`.

Kept unchanged:

- `src/Tweak.x` from a2e50, because that is the non-crashing build with the correct menu opener.

Binary evidence checked from `Facebook(3)` and `FBSharedFramework(90)`:

- `_TtC11FBDogFoodUI17DogFoodController`
- `getNagSheetWithSession:title:message:switchButtonText:snoozeButtonText:snoozeEnabled:onSwitch:onSnooze:`
- `FBDogFood-managedPhoneFlag`
- `FBAppJobDogFoodWarm`
- `FBAppJobDogFoodCold`
- `TB,R,N,V_enableDogfoodingView`
- `_isDogfoodingView`

Crash `Facebook-2026-05-28-061058.ips`:

- SIGABRT on main thread during application initialization.
- Top frames show `class_getInstanceMethod` called from `FBTweaks.dylib`, causing Facebook dynamic method resolution and exception.
- Fix: no broad class scan / no `objc_copyClassList` in `FBGRMCGateHooks.xm`.

Runtime fixes:

- Embedded `ReactMobileConfigMetadata.json.gz` generated from the uploaded `ReactMobileConfigMetadata(1).json`.
- Catalog loads from disk paths first and embedded gzip fallback.
- Counts: 5374 total params, 4676 bool params.
- Runtime Browser now has All / Bool / iOS / Overrides.
- Switch OFF writes forced `NO`, not clear. Use clear/reset actions to remove override.

DogFood fixes:

- Adds `src/Hooks/FBGRDogFoodHooks.xm` without constructor UI work.
- Writes `FBDogFood-managedPhoneFlag` only when toggled.
- Adds native DogFood action using the binary-confirmed Swift class/method.

MobileConfig hook fixes:

- No constructor.
- No global class scan.
- Installs only when a toggle is changed or cache refresh sees overrides.
- Hot path uses RAM cache only.
