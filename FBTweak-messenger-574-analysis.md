# Messenger 574 runtime analysis and implementation recap

## Scope and provenance

- Base branch: `flags`
- Base commit: `8123092` (`fix(build): avoid Logos orig inside ternary expression`)
- App: Messenger 574.0.0, build 1035554267
- Bundle/executable: `com.facebook.Messenger` / `Messenger`
- IPA SHA-256: `a109ceeaac210f46f559d8aee96c7a6b331ce7ddb33eb0f1e1420d97d1787d2c`
- Main images inspected: `Messenger`, `LightSpeedCore`, `LightSpeedEngine`

The IPA was inspected with LIEF and Capstone plus manual Mach-O Objective-C
metadata and chained-fixup decoding. `r2pipe` could be installed, but no
radare2 executable was available in the container, so no conclusion depends on
radare2 output.

## What was retained from `flags`

The original branch established the right safety model:

1. exact and idempotent hooks rather than constructor-time global scans;
2. one original IMP per validated Objective-C method;
3. fishhook for imported C functions instead of modifying signed `__TEXT`;
4. registered `NSUserDefaults` with reload notifications and hot-path caches;
5. UIKit-native context-menu presentation, with no custom preview surface.

Facebook-only owners such as `FBTabBarViewController`,
`FBInternalSettingsViewControllerFromSession` and
`FBShouldEnableInternalSettings` do not exist as usable Messenger exports and
are not linked into the Messenger target. The explicit source list also omits
the base branch's independent settings constructor and Facebook catalog assets.

## Validated host and Objective-C gates

The Messenger tab host is:

```text
_TtC25MDSModernTabBarController25MDSModernTabBarController
-viewDidAppear:  v20@0:8B16
```

Validated employee methods:

```text
MBUISimpleParticipantModel                  -isEmployee
MBQPreviewParticipant                       -isEmployee
MSGParticipantContact                       -isEmployee
MSGMentionPlaceholderParticipant            -isEmployee
MSGPublicChatParticipantAdapter             -isEmployee
MSGPublicChatMemberAdapter                  -isEmployee
FBWKWebView                                 -setIsEmployee:
FBWKWebViewDelegateAdaptor                  -setIsEmployee:
```

Validated internal availability providers:

```text
Internal Settings  MSGEBDebugSettingsViewController              +isAvailable:
Internal Tools     MSGEBDebugUserSettingsOverrideViewController  +isAvailable:
```

Their class-method ABI is `B24@0:8@16`. The replacements preserve the original
result unless the corresponding quick switch is enabled. They are intentionally
separate: enabling Internal Settings does not also expose User Settings Override.

## Packed MobileConfig keys

`LightSpeedCore` imports `MSGCSessionedMobileConfigGetBoolean` from
`LightSpeedEngine`, so fishhook covers its import slot without modifying signed
code. Disassembly found 96 direct calls to that stub. At those call sites,
`LightSpeedCore` copies two 16-byte halves of a descriptor to the stack and
passes its address in `x1`; it does not pass the packed key in `x1`.

The mapped C ABI is:

```c
struct MSGCMobileConfigParameterDescriptor {
    const char *configName;       // +0
    const char *parameterName;    // +8
    uint64_t rawValue;            // +16
    uint64_t unitType;            // +24
};

BOOL MSGCSessionedMobileConfigGetBoolean(
    void *session,
    const struct MSGCMobileConfigParameterDescriptor *parameter,
    BOOL fallback,
    BOOL readOptions);
```

The previous implementation declared `x1` as `uint64_t key`. It consequently
compared the temporary stack address against packed keys, so every menu switch
missed the C reader. The replacement now reads `parameter->rawValue` at `+16`,
returns the forced value for a mapped key, and delegates all unmatched reads
with the original pointer and arguments unchanged.

Calls made inside `LightSpeedEngine` do not cross the `LightSpeedCore` import
slot. The effective path therefore also hooks the exact Objective-C readers
present in the 574 Mach-O, preserving their validated encodings:

```text
FBMobileConfigContextManager
FBMobileConfigSessionlessContextManager
FBMobileConfigUserSessionContextManager

-getBool:
-getBool:withDefault:
-getBool:withOptions:
-getBool:withOptions:withDefault:
-getBoolWithoutLogging:
-getBoolWithoutLogging:withDefault:
```

The three parameter structs are all single-`uint64_t` ABI wrappers. These are
Objective-C method hooks (`MSHookMessageEx`), so internal Engine reads are
covered without an inline C hook or signed `__TEXT` mutation.

### 1.1.116 crash and corrected trampoline ownership

The device crash report for Messenger 574.0.0 (1035554267) and the packaged
1.1.116 dylib were checked together before changing the hook design:

- the crash is a main-thread stack overflow (`EXC_BAD_ACCESS` in the stack
  guard), with 21,315 frames and a recorded recursion depth of 10,647;
- the report's `FBTweak.dylib` UUID is
  `5717e1d5-741d-3024-b0d7-131e9ed3394d`, exactly matching the dylib extracted
  from the `.deb`;
- `FBTweak+0xB804` is the return from the indirect call through the selected
  descriptor's `original` field, while `FBTweak+0xBA58` is inside the old
  receiver-based descriptor lookup after `sel_registerName`;
- `LightSpeedEngine+0x172BB0` is the directly declared
  `-[FBMobileConfigSessionlessContextManager getBool:]`. At `+0x172BD0` it
  finishes an `objc_msgSendSuper2` of the same `getBool:` selector to
  `FBMobileConfigContextManager`.

The previous shared replacement selected an `old` trampoline from the runtime
class of `self`. A super call keeps the sessionless instance as `self`, so the
base-class replacement selected the sessionless trampoline again and recreated
the same call forever.

Every one of the ten readers now has a distinct ABI-compatible replacement and
the exact `old` stub returned by `MSHookMessageEx` for that class/method pair.
Installation also uses `class_copyMethodList` to accept only methods declared
directly by the target class; it no longer mistakes an inherited method for a
second hook target.

| Feature | Config.parameter | Packed key |
|---|---|---:|
| Employee | `fb_ford.is_employee` | `0x008103fe000b1472` |
| Employee | `messenger_secret_conversation_deprecation.is_employee` | `0x008104aa0006174b` |
| Internal Settings | `fb_ford.can_access_internal_settings` | `0x008103fe00051470` |
| Internal Tools | `labyrinth_ui.is_dev_debug_only_ux_enabled` | `0x00810130001606e3` |
| Internal Tools | `labyrinth_ui.is_eb_debug_menu_enabled` | `0x00810130007c071b` |
| Internal Tools | `labyrinth_ui.is_eb_debug_advanced_menu_enabled` | `0x00810130007d071c` |
| Internal Tools | `labyrinth_ui.is_eb_debug_user_settings_override_enabled` | `0x008101300140078a` |
| Homebase | `homebase_ios.enable_mailbox_sync` | `0x0081065800001c1b` |
| Homebase | `homebase_ios.enable_homebase_tab` | `0x0081065800011c1c` |
| Homebase | `homebase_ios.enable_calendar_rsvp_status` | `0x0081065800051c1d` |
| Homebase | `homebase_ios.enable_list_card_add_row` | `0x2081065800101c1e` |
| Household | `homebase_ios.thread_settings_enabled` | `0x0081065800131c1f` |

The native internal section identifier `msg_settings_internal_settings_section`
is registered in the Settings section list. Messenger 574 also contains
extensive Homebase/Household UI classes.
The only Household-named descriptors in this build are the string descriptors
`homebase_strings.omnipicker_household_title` and
`homebase_strings.omnipicker_household_subtitle`; there is no separate local
Household boolean. The Household switch therefore forces only the verified
mailbox and Homebase thread-settings paths. It stays independent from the
Homebase tab switch and does not invent local household membership.

## Long-press behavior

The host hook attaches a native context-menu interaction to the tab bar and to
a top-leading view only when its accessibility label, identifier or runtime
class identifies a Messenger logo. The image also contains the exact identifiers
`MSGMessengerWordmarkView`, `messengerLogoImageView` and `messenger_logo`; the
accessor is used only after a top-leading geometry check. This avoids hijacking
unrelated navigation buttons.

The custom panel/alpha animation and the later synthetic 44-point glass capsule
were both removed. `UIContextMenuInteraction` owns the five stateful actions.
For the logo, `UITargetedPreview` uses that existing view; for the full tab bar,
the implementation hit-tests the press and chooses the real compact control or
child view below the finger. UIKit therefore owns the native iOS 26 Liquid
Glass presentation and forward/dismissal morph. This path constructs neither a
custom fade nor an intermediate preview bubble.

## Boundaries

- Disabled switches always return the original Messenger values.
- No inline C hook or signed executable-page mutation is used.
- Employee/Internal are local presentation and client-code gates only.
- Household account membership and mutations remain server-side; only verified
  local mailbox/thread-settings gates are affected.
- Server authorization, remote metadata and account provisioning remain under
  the server/account's control.
- Packed keys are validated for Messenger 574 and must be rechecked for a new
  app build.
