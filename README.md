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
its `UITargetedPreview` uses the real logo or tab control below the finger as
the morph source. No detached blur/glass view or intermediate bubble is
created. The menu contains only:

- Employee
- Internal Settings
- Internal Tools
- Homebase
- Household

Internal Tools automatically enables Internal Settings and Employee. Homebase
and Household are independent local switches. Messenger 574 has no standalone
Household membership boolean, so Household is limited to its verified local
Homebase mailbox/thread-settings paths and never fabricates account membership.

The visible Messenger Settings controller is asked to rebuild immediately after
a switch changes. Tab-model gates are launch-consumed, so reopen Messenger for
Homebase tab changes.

## Mapped runtime behavior

- Employee: `fb_ford.is_employee`, the secret-conversation employee gate, six
  validated `-isEmployee` models and two `-setIsEmployee:` propagation points.
- Internal Settings: `fb_ford.can_access_internal_settings` plus the native
  `MSGEBDebugSettingsViewController +isAvailable:` provider.
- Internal Tools: four validated `labyrinth_ui` debug gates plus
  `MSGEBDebugUserSettingsOverrideViewController +isAvailable:`.
- Homebase: mailbox sync, tab, calendar RSVP and list add-row.
- Household: mailbox sync and Homebase thread settings. Account/server support
  is still required for household membership, remote data and mutations.

The imported C reader receives a pointer to a 32-byte parameter descriptor, not
the packed key itself. This branch extracts `rawValue` at descriptor offset 16;
the previous `uint64_t x1` declaration compared a stack address and therefore
could not match any requested override.

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
