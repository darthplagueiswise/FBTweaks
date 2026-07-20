# FBTweak v4.1 — RN gates and native MobileConfig addendum

## Scope

This addendum is based on the supplied `Facebook`, `FBSharedFramework(9)`, `FBSharedDynamicFramework`, `FBReactNativeProductsFramework` and `FBRarelyUsedFramework` images.

Tools used: LIEF, Capstone, `llvm-objdump`, Objective-C metadata parsing and ARM64 xref scans. `r2pipe` was installed, but the radare2 executable was unavailable in the container; no finding is attributed to r2 output.

## FBReactNativeProductsFramework families

### Employee identity and propagation

The RN image does not own a zero-argument employee identity getter. Confirmed propagation/consumers are:

```objc
RCTCurrentViewer -setIsEmployee:                         v20@0:8B16
FBInspirationMediaCompositionViewController
-isEligibleForDebugIndicatorWithEmployeeCondition:      B20@0:8B16
```

The identity owners remain in the executable/shared images. FBTweak forces these RN arguments only when Employee is enabled.

### Internal test user and test user

No independent owner is implemented by the RN image. The confirmed identities are in `FBIdentitySwitcherGatingHelper`:

```objc
-isInternalTestUser:
-isTaggingInternalTestUserEnabled:
```

Test User now also enables the concrete native Internal Settings C gate and its configuration setters without changing `-isEmployee`.

### Dogfood

`_ios_creation_meaningful_dogfooding` is an imported MobileConfig DATA descriptor, not a function. RN also contains the component wrapper and instrumentation labels, but no safe local BOOL dogfood identity owner. Known client gates remain in the shared/executable images and are kept separate from MobileConfig DATA.

### React Native Internal Settings

Confirmed classes and route:

```text
RCTDevMenu
RCTDevMenuItem
RCTDevSettings
FBReactNativeInternalSettingsMenuItemHandler
fb://rninternalsettings
```

Test User, Employee or the explicit RN Internal toggle can activate the mapped RN dev gates. C imports `RCTDevLoadingViewGetEnabled/SetEnabled` remain latched and require restart to turn off.

### TestFlight, beta and build channel

No callable TestFlight membership/internal-build predicate was found in the RN image. `buildFlavor`, `deviceBuildType` and `isTestFlightApp` occurrences are telemetry/data fields. The only confirmed callable gate is `METAOSBuildIsBeta(void)`, exposed honestly as an OS beta gate.

## Native MobileConfig UI

The alert `Failed to fetch param info from server!` belongs to `FBRarelyUsedFramework` and is emitted by the remote QE-info path. FBTweak does not suppress it or fabricate a response.

The native controller is now hooked only after its framework/class is available:

```objc
FBMobileConfigDebugViewController -viewDidLoad
FBMobileConfigDebugViewController
-selectParam:key:configName:backendType:backendName:
```

Before the native controller resolves a parameter, FBTweak refreshes local reader/context capture. This addresses the client-side late-loading race. A persistent remote failure still indicates unavailable server QE metadata, credentials or network access.
