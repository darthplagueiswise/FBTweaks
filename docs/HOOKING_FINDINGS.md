# FBTweaks hooking findings — Facebook/FBSharedFramework 106

Validated input files: Facebook(6), FBSharedFramework(106), ReactMobileConfigMetadata(7).json, IDNameMapping(4).zip.

## MobileConfig flags

Use `MSHookMessageEx`, not fishhook, for ObjC MobileConfig BOOL getters. Validated selectors:

```objc
getBool:
getBool:withDefault:
getBool:default:
getBool:defaultValue:
getBool:withOptions:
getBool:withOptions:withDefault:
getBoolWithoutLogging:
getBoolWithoutLogging:withDefault:
getBoolWithoutExposure:
getBoolWithoutExposure:withDefault:
```

Validated owner classes:

```text
FBMobileConfigContextManager
FBMobileConfigUserSessionContextManager
FBMobileConfigSessionlessContextManager
FBMobileConfigAdminIDContextManager
FBMobileConfigContextObjcImpl
FBMobileConfigGlobalContext
FBMobileConfigAPI
FBMobileConfigFBTAPI
FBMobileConfigFBTContextManager
RCTMobileConfigNative
MobileConfigModule
```

The hook hot path must read only a RAM cache by `slotId`. No `NSUserDefaults`, `NSString`, `NSDictionary`, logging, or class scanning inside the hooked getter.

## LiquidGlass

SDK26 path is ObjC/Swift-bridged helper based:

```text
_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper
_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper
```

Validated methods include `isEnabled`, `isHomeFeedHeaderEnabled`, `isGlassRenderingOptimizationEnabled`, and `isLegibilityBlurEnabled`. `METAIsLiquidGlassEnabled` fishhook remains only as a fallback for older builds.

## Runtime catalog

`ReactMobileConfigMetadata(7).json` contains 5377 params and 4679 boolValue params. FBTweaks now loads metadata first from the app data container (`Documents/FBTweaks`, `Library/Application Support/FBTweaks`, `Library/Caches/FBTweaks`, `tmp/FBTweaks`), then shared app-support paths, dylib-relative resources, main bundle resources, and finally the embedded gzip catalog.

## IDNameMapping

`IDNameMapping(4).zip` is not encrypted; it is a gzip-compressed JSON analytics mapping, not a feature-flag mapping. It is not used for MobileConfig overrides.
