# FBTweak v4.0 — new framework gates and React Native internal surfaces

## Binaries analyzed

- `Facebook`
- `FBSharedFramework(9)`
- `FBSharedDynamicFramework`
- `FBReactNativeProductsFramework`
- `FBRarelyUsedFramework`

The analysis used LIEF, Capstone, `llvm-objdump`, Objective-C metadata parsing and ARM64 xref scans. `radare2` was not available in the container, so no result in this report is attributed to r2.

## FBReactNativeProductsFramework mapping

### Employee identity

The framework does not own a zero-argument `-isEmployee` identity getter. It contains a consumer in `FBRestyleHubViewController -viewWillAppear:` that sends `isEmployee` to another object.

Known local identity owners remain in the executable/shared frameworks. The RN-specific employee gate is:

```objc
FBInspirationMediaCompositionViewController
- (BOOL)isEligibleForDebugIndicatorWithEmployeeCondition:(BOOL)condition;
```

### Employee state propagation

```objc
RCTCurrentViewer
- (void)setIsEmployee:(BOOL)value;
```

This is the concrete RN bridge for propagating employee state. The new known group forces the setter argument to `YES` when Employee/Internal is enabled.

### Internal test user / test user

No direct `isInternalTestUser` or `isTestUser` owner was found in this framework. Those selectors are owned by `FBIdentitySwitcherGatingHelper` in `FBSharedFramework` and are now hooked separately.

### Dogfood / dogfooding

The framework imports:

```text
_ios_creation_meaningful_dogfooding
```

It is a DATA/MobileConfig descriptor exported by `FBSharedFramework`, not a function. It is therefore handled through the native MobileConfig override path, never through fishhook as a BOOL function.

The framework also contains `FBStoriesComposerMeaningfulDogfoodingComponentWrapper`, which is a component implementation rather than the eligibility gate that decides whether the component is inserted.

### Internal tools and RN Internal Settings

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

Known hooks now cover Dev Menu availability, shake gesture, hotkeys, keyboard shortcuts, disabled menu items and device-debugging availability.

The imported C gates:

```text
RCTDevLoadingViewGetEnabled  BOOL(void)
RCTDevLoadingViewSetEnabled  void(BOOL)
```

were ABI-verified in `FBSharedFramework` and are fishhooked only when RN Internal Settings was already enabled at launch or explicitly enabled from the tweak UI. Once installed, turning these C hooks off requires restarting Facebook.

### TestFlight / beta / build channel

No TestFlight identity predicate is callable in `FBReactNativeProductsFramework`. The `deviceBuildType` and `buildFlavor` methods in this framework are telemetry, not gates, and are not modified.

The confirmed client-side beta gate is:

```text
METAOSBuildIsBeta  BOOL(void)
```

exported by `FBSharedFramework` and imported by the Facebook executable. The new Beta Build toggle fishhooks this import. It does not fabricate an App Store receipt, TestFlight install state or server build entitlement.

## Expanded known gates

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
- `MBUISimpleParticipantModel -isEmployee` when the dynamic framework is loaded

### Internal/test user

- `FBRichPushNotificationTypeTraits +_isEmployeeOrTestUser:`
- `FBIdentitySwitcherGatingHelper -isInternalTestUser:`
- `FBIdentitySwitcherGatingHelper -isTaggingInternalTestUserEnabled:`

### Dogfood

- `FBIdentitySwitcherGatingHelper -isInGroupingByACDogfooding:`
- `FBBugReportInitialCoordinator` dogfooding assistant state
- `FBSnacksAdsDeliveryConfig -enableDogfoodingView`
- late-loaded Rage Shake dogfooding state/model/view-controller selectors

### Internal Settings

Employee/Internal now also enables the imported native gate:

```text
FBShouldEnableInternalSettings
```

EasyGating remains separate because it is a broad gate used by unrelated products.

## Runtime browser corrections

- A forced override is checked before the original implementation is called.
- Sweep matching now uses exact selector allowlists instead of matching `employee`/`dogfood` anywhere in the class or image path.
- Sweep overrides store provenance (`sweep:employee`, `sweep:dogfood`, `sweep:internaldebug`).
- Turning a sweep off removes only overrides created by that sweep.
- Manual overrides remain untouched.

## Native MobileConfig UI

Opening the native Internal Settings controller now installs the post-launch MobileConfig reader/context capture before presenting the UI. This reduces the race where no matching context manager exists yet.

It does not fake a successful server response for `fetchQEInfoSynchronously`. The native alert “Failed to fetch param info from server” is emitted by `FBRarelyUsedFramework` when remote QE metadata cannot be fetched. Local overrides remain available through the captured MetaMap/context/OverridesTable path.
