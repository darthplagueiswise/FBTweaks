# FBTweak — Messenger Flags

Theos/rootless branch for Messenger iOS 574.0.0 (1035554267), arm64, built
with the iPhoneOS 26.2 SDK and a minimum deployment target of iOS 16.3. It is
based on `flags` commit `8123092`.

## What the five switches do

- **Employee** forces the current session's validated
  `fb_ford.is_employee` and secret-conversation employee descriptors. It also
  propagates that value through the exact Messenger consumers that correspond
  to the original `flags` branch: `MBUISimpleParticipantModel`, both
  `FBWKWebView` setters, `LSRageShakeView`, and the Bloks Lab deeplink helper.
- **Internal Settings** implies Employee and additionally forces
  `fb_ford.can_access_internal_settings`.
- **Internal Tools** implies Internal Settings and Employee, enables the four
  mapped `labyrinth_ui` debug descriptors, and enables the imported internal
  EasyGating path.
- **Homebase** enables the mapped local tab, mailbox, calendar, and list gates.
- **Household** implies Homebase and enables the verified Homebase mailbox and
  thread-settings paths. It does not create server-side household membership.

The important identity path is not a participant-model sweep. Messenger imports
`LSShouldEnablePluginBasedOnMobileConfigParam`, the direct counterpart of the
Facebook branch's `FBShouldEnableInternalSettings` gate. Its second argument is
a tagged descriptor pointer; after clearing bit 0, the packed MobileConfig key
is at descriptor offset `+16`. The tweak forces the exact Employee/Internal
keys at that final plugin decision as well as at the imported C reader.

Messenger's `__DATA_CONST.__got` is `S_NON_LAZY_SYMBOL_POINTERS`, not
`S_REGULAR`, and has the required indirect symbol table. The target therefore
uses fishhook for the three imported functions and never patches signed
`__TEXT`. The vendored implementation includes the PAC/`__AUTH_CONST` support
from the maintained `opa334/fishhook` fork.

## Long-press menu

Long-press the Messenger tab bar. When the Messenger logo/wordmark can be
identified conservatively in the top navigation area, it is an alternative
entry point. The menu is a native `UIContextMenuInteraction`; its
`UITargetedPreview` uses the existing logo or tab control under the finger, so
UIKit owns the iOS 26 Liquid Glass lift, morph, and dismissal. No custom fade,
detached glass capsule, or intermediate bubble is created.

The visible Settings controller is refreshed after a toggle. User-scoped
plugins and the tab model may already be cached, so reopen Messenger after
changing Employee, Internal Settings/Tools, Homebase, or Household.

These are local client/UI gates. They do not mint an employee token, grant
server authorization, or provision unsupported account data.

See [FBTweak-messenger-574-analysis.md](FBTweak-messenger-574-analysis.md) for
the binary evidence, ABI mapping, and crash analysis.

## Build

```sh
export THEOS=~/theos
./build.sh rootless
```

The package filter and install process target `com.facebook.Messenger` /
`Messenger`. The explicit source list excludes the Facebook-only settings
browsers, constructors, and catalogs from the base branch.
