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

The identity owners remain in the executable/shared images. FBTweak forces the RN employee input while preserving the original method's remaining eligibility checks.

### Internal test user and test user

No independent identity owner is implemented by the RN image. Confirmed identities are in `FBIdentitySwitcherGatingHelper`:

```objc
-isInternalTestUser:
-isTaggingInternalTestUserEnabled:
```

Test User also enables the concrete native Internal Settings C gate and configuration setters without changing `-isEmployee`.

### Dogfood

`_ios_creation_meaningful_dogfooding` is an imported MobileConfig DATA descriptor, not a function. RN contains component wrappers and instrumentation labels, but no safe local zero-argument dogfood identity owner. Confirmed client gates remain in the executable/shared/dynamic images and stay separate from MobileConfig DATA.

### React Native Internal Settings

Confirmed classes, C imports and route:

```text
RCTDevMenu
RCTDevMenuItem
RCTDevSettings
FBReactNativeInternalSettingsMenuItemHandler
RCTDevLoadingViewGetEnabled
RCTDevLoadingViewSetEnabled
fb://rninternalsettings
```

Employee, Test User or the explicit RN Internal toggle can activate availability, DevMenu, shake, hotkeys, menu-item and DevLoadingView gates. Profiler, active hot-loading state, sampling-profiler-on-launch and perf-monitor visibility remain user-controlled because they are operational states, not availability gates.

The ObjC Logos group waits until at least one RN target class actually exists. A filtered bundle-load observer and the tab host retry the idempotent installer for late-loaded RN/Dynamic/RarelyUsed images.

### TestFlight, beta and build channel

No callable TestFlight membership/internal-build predicate was found in the RN image. `buildFlavor`, `deviceBuildType` and `isTestFlightApp` occurrences are telemetry/data fields, not verified global gates.

The only confirmed callable gate is:

```c
BOOL METAOSBuildIsBeta(void);
```

It is imported by `Facebook` and hooked through fishhook/GOT. It is exposed as an OS beta predicate, not as a fake TestFlight receipt or internal build.

## Other executable/framework families

### Employee identity/state propagation

The implementation covers verified getters, setters and propagation points across the executable, Shared, Dynamic, RN and RarelyUsed images, including:

```text
FBUserPreferences
FBBugReportConfiguration
FBLoggedOutImageNetworkerConfiguration
FBSessionImageNetworkerConfiguration
FBRichPushNotificationTypeTraits
FBWKWebView / FBWKWebViewDelegateAdaptor
RCDMobileConfigParams
FBLoom
MBUISimpleParticipantModel
```

### Dogfood/internal tools

Known local gates include:

```text
FBBugReportInitialCoordinator
FBSnacksAdsDeliveryConfig
FBIdentitySwitcherGatingHelper -isInGroupingByACDogfooding:
FBClientRageShakeBugReporterIssueComponentState
FBClientRageShakeBugReporterIssueModel
FBClientRageShakeBugReporterIssueViewController
```

`FFDBInternalSettingsWebViewController -isInternLoggedIn` is treated only as a local UI gate. It does not create or replace an internal authentication token.

## Native MobileConfig UI

The alert `Failed to fetch param info from server!` belongs to `FBRarelyUsedFramework` and is emitted by the remote QE-info path.

The native controller is installed only after its framework/class exists:

```objc
FBMobileConfigDebugViewController -viewDidLoad
FBMobileConfigDebugViewController
-selectParam:key:configName:backendType:backendName:
```

The select method carries two `const std::string &` arguments, so the hook is implemented in Objective-C++ with owned copies for retry safety.

Current behavior:

1. warm the safe MobileConfig readers and context capture before native selection;
2. if no context exists yet, defer the first typed original call briefly;
3. when the exact transient param-info alert appears for the first time, suppress only that alert and retry the same typed selection once;
4. if the second attempt fails, preserve the native alert and add `Open FBT Local Override`;
5. never fabricate QE metadata or suppress persistent server failure.

A persistent failure still indicates unavailable remote QE metadata, credentials, context or network access. The local fallback remains useful for captured values and override-table operations that do not require the employee-only metadata endpoint.

## Safety boundaries

- no `MSHookFunction` or inline patch on signed `__TEXT`;
- C functions are hooked only when imported/GOT and ABI-confirmed;
- Swift/late ObjC methods use one original pointer per selector;
- DATA descriptors are never treated as functions;
- global class scans remain manual/on-demand, never in the constructor;
- Runtime BOOL sweep entries record provenance and are removed when their specific sweep toggle is turned off.
