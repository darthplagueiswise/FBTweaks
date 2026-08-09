# FBTweak — Messenger Flags

Branch Theos/rootless for Messenger iOS 574.0.0 (build 1035554267), arm64,
using the iPhoneOS 26.2 SDK with a minimum deployment target of iOS 16.3.

This branch starts at `flags` commit `8123092` and keeps its safe runtime
architecture: exact Objective-C selectors—including the three native
MobileConfig context managers—use `MSHookMessageEx`, imported C readers retain
fishhook/GOT as a fallback, preferences are cached away from hot paths, and no
signed `__TEXT` page is patched.

## Compact long-press menu

Long-press the Messenger tab bar. A second entry point is attached when the
Messenger logo/title image can be identified conservatively in the top
navigation area. UIKit presents a native `UIContextMenuInteraction`; on iOS 26
its `UITargetedPreview` morphs the Liquid Glass menu to and from the logo or a
compact glass capsule at the tab-bar press point. It contains only:

- Employee
- Internal Settings
- Internal Tools
- Homebase
- Household

Internal Tools automatically enables Internal Settings and Employee. Household
automatically enables Homebase because Messenger 574 contains Household UI and
copy descriptors but no independent Household boolean descriptor.

Some gates are consumed while Messenger builds Settings and its tabs, so reopen
the app after changing switches.

## Mapped runtime behavior

- Employee: `fb_ford.is_employee`, the secret-conversation employee gate, six
  validated `-isEmployee` models and two `-setIsEmployee:` propagation points.
- Internal Settings: `fb_ford.can_access_internal_settings`.
- Internal Tools: four validated `labyrinth_ui` debug gates plus the two native
  encrypted-backup debug providers.
- Homebase: mailbox sync, tab, calendar RSVP, list add-row and thread settings.
- Household: uses the Homebase dependency chain. Account/server support is still
  required for remote data or actions.

The overrides are local UI/client gates. They do not mint an employee token,
grant server authorization or provision unsupported account data.

See [FBTweak-messenger-574-analysis.md](FBTweak-messenger-574-analysis.md) for
the binary evidence and exact packed keys.

## Build

```sh
export THEOS=~/theos
./build.sh rootless
```

The package filter and install process both target `com.facebook.Messenger` /
`Messenger`. Its explicit source list excludes every Facebook settings browser,
constructor and catalog asset retained in the base branch. The CI build uses
`iPhoneOS26.2.sdk`, rootless, arm64 and `FINALPACKAGE=1`.
