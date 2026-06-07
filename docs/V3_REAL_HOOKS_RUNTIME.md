# FBTweaks v3

This tree is rebuilt from the working longpress base.

## Tweak.x

`Tweak.x` only opens the menu. It hooks the working tab button classes:

- `FDSTouchStateAnnouncingControl`
- `FBTabBarItemDefaultView`

It does not install MobileConfig, LiquidGlass, DogFood, runtime scanning, fishhook or global UIKit hooks at startup.

## Fishhook

Fishhook is used on demand by `FBGRMCGateHooksEnsureInstalled()` for validated C/C++ bool bridges:

- `__ZN12mobileconfig14getBoolDefaultEy`
- `__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc`

The main override path is still `MSHookMessageEx` over real Objective-C MobileConfig selector signatures.

## Runtime browsers

All three runtime screens have direct toggles:

- MobileConfig Runtime Browser: slotId/key-backed metadata flags.
- Executable Bool Runtime: Objective-C BOOL getters inside `Facebook.app/Facebook`.
- FBSharedFramework Bool Runtime: Objective-C BOOL getters inside `FBSharedFramework.framework`.

Switch ON means Force YES. Switch OFF means Force NO. There is no confusing per-row “apply hook” action.
