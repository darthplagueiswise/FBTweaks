# FBTweak v4.1 — new framework gates, RN internal surfaces and native MobileConfig assist

## Binaries analyzed

- `Facebook`
- `FBSharedFramework(9)`
- `FBSharedDynamicFramework`
- `FBReactNativeProductsFramework`
- `FBRarelyUsedFramework`

The analysis used LIEF, Capstone, `llvm-objdump`, Objective-C metadata parsing and ARM64 xref scans. `radare2` was not available in the container, so no result in this report is attributed to r2.

## FBReactNativeProductsFramework mapping

### Employee identity

The framework does not own a zero-argument global `-isEmployee` identity getter. It contains a consumer in `FBRestyleHubViewController -viewWillAppear:` that sends `isEmployee` to another object.

The RN-specific eligibility consumer is:

```objc
FBInspirationMediaCompositionViewController
- (BOOL)isEligibleForDebugIndicatorWithEmployeeCondition:(BOOL)condition;
```

The hook passes `YES` as the employee input and still executes the original, preserving all non-employee conditions.

### Employee state propagation

```objc
RCTCurrentViewer
- (void)setIsEmployee:(BOOL)value;
```

This is the concrete bridge used to propagate employee state into React Native.

### Internal test user / test user

No direct `isInternalTestUser` owner was found in this framework. The actual selectors are owned by the Swift `FBIdentitySwitcherGatingHelper` in `FBSharedFramework`:

```text
isInternalTestUser:
isTaggingInternalTestUserEnabled:
```

Test User is kept distinct from Employee. It opens Internal Settings/test-user gates without forcing employee-only getters.

### Dogfood / dogfooding

The framework imports:

```text
_ios_creation_meaningful_dogfooding
```

It is a DATA/MobileConfig descriptor exported by `FBSharedFramework`, not a function. It remains on the native MobileConfig override path and is never fishhooked as a BOOL function.

The framework also contains `FBStoriesComposerMeaningfulDogfoodingComponentWrapper`, which renders a component but is not the eligibility gate that inserts it.

### Internal tools and React Native Internal Settings

Concrete classes:

```text
RCTDevMenu
RCTDevMenuItem
RCTDevSettings
RCTDevMenuConfiguration
FBReactNativeInternalSettingsMenuItemHandler
```

Concrete route and identifier:

```text
fb://rninternalsettings
kReactNativeInternalSettingsMenuItemIdentifier
```

All confirmed enablement gates are covered:

```text
RCTDevMenu
- devMenuEnabled / setDevMenuEnabled:
- shakeToShow / setShakeToShow:
- profilingEnabled / setProfilingEnabled:
- hotLoadingEnabled / setHotLoadingEnabled:
- hotkeysEnabled / setHotkeysEnabled:
- keyboardShortcutsEnabled / setKeyboardShortcutsEnabled:

RCTDevMenuItem
- isDisabled / setDisabled:

RCTDevSettings
- isDeviceDebuggingAvailable
- isHotLoadingAvailable
- isShakeToShowDevMenuEnabled / setIsShakeToShowDevMenuEnabled:
- isShakeGestureEnabled / setIsShakeGestureEnabled:
- isProfilingEnabled / setProfilingEnabled:
- isHotLoadingEnabled / setHotLoadingEnabled:
```

State/action methods such as `isElementInspectorShown`, `isPerfMonitorShown` and `startSamplingProfilerOnLaunch` are deliberately not forced: they represent the current active tool state, not availability gates.

The imported C gates:

```text
RCTDevLoadingViewGetEnabled  BOOL(void)
RCTDevLoadingViewSetEnabled  void(BOOL)
```

are fishhooked only when RN Internal Settings is enabled. Once installed, disabling them requires a Facebook process restart.

### TestFlight / beta / build channel

No callable TestFlight-receipt predicate exists in `FBReactNativeProductsFramework`. Its `deviceBuildType` and `buildFlavor` values are telemetry, not global gates.

The confirmed client-side beta gate is:

```text
METAOSBuildIsBeta  BOOL(void)
```

It is exported by `FBSharedFramework` and imported by the Facebook executable. The OS Beta toggle fishhooks this import. It does not fabricate an App Store/TestFlight receipt, internal build entitlement or server build channel.

## Expanded known gates across executable/frameworks

### Employee identity and propagation

- `FBUserPreferences -isEmployee/-setEmployee:`
- `FBBugReportConfiguration -isEmployee/-setIsEmployee:`
- `FBProductTagCreationLogger -isEmployee`
- `FBSnacksThreadOwnerMessengerContact -isEmployee`
- `FBLoggedOutImageNetworkerConfiguration -isViewerEmployee`
- `FBSessionImageNetworkerConfiguration -isViewerEmployee`
- `FBWKWebView -setIsEmployee:`
- `FBWKWebViewDelegateAdaptor -setIsEmployee:`
- `RCDMobileConfigParams -isEmployee` and its employee constructor argument
- `FBLoom` employee session propagation argument
- `RCTCurrentViewer -setIsEmployee:`
- `MBUISimpleParticipantModel -isEmployee` after the dynamic framework loads

### Internal/test user

- `FBRichPushNotificationTypeTraits +_isEmployeeOrTestUser:`
- `FBIdentitySwitcherGatingHelper -isInternalTestUser:`
- `FBIdentitySwitcherGatingHelper -isTaggingInternalTestUserEnabled:`
- test-user-only `FBBugReportConfiguration` Internal Settings setters
- native `FBShouldEnableInternalSettings` import

### Dogfood

- `FBIdentitySwitcherGatingHelper -isInGroupingByACDogfooding:`
- `FBBugReportInitialCoordinator` dogfooding assistant state
- `FBSnacksAdsDeliveryConfig -enableDogfoodingView`
- late-loaded Rage Shake dogfooding state/model/view-controller selectors

EasyGating remains a separate opt-in toggle because it is broad and affects unrelated products.

## Runtime browser corrections

- A forced override is checked before the original implementation is called.
- Sweep matching uses exact selector allowlists instead of matching `employee` or `dogfood` anywhere in a class/image path.
- Sweep overrides store provenance (`sweep:employee`, `sweep:dogfood`, `sweep:internaldebug`).
- Turning a sweep off removes only overrides created by that sweep.
- Manual overrides remain untouched.
- No global class/dladdr sweep runs in the constructor.

## Native MobileConfig UI

The advanced UI is loaded from `FBRarelyUsedFramework`. The typed selector is:

```objc
-selectParam:key:configName:backendType:backendName:
```

with two `const std::string &` parameters, so the assist module is Objective-C++.

Behavior implemented:

1. install local readers/context capture when the native MobileConfig controller loads;
2. preserve an owned copy of the exact selected parameter/config;
3. when no context is captured yet, delay the first call by 200 ms;
4. suppress only the first exact `Failed to fetch param info from server` alert;
5. warm contexts and retry the same selection once after 550 ms;
6. if the second request still fails, preserve the native error and add `Open FBT Local Override`.

The tweak does not fabricate the remote QE response returned by `fetchQEInfoSynchronously`. The fallback opens the local captured-key/OverridesTable browser, which does not depend on the employee-only QE names/info endpoint.
