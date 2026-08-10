# Messenger 574 runtime analysis and implementation recap

## Scope and provenance

- Base branch/commit: `flags` at `8123092`
- Working branch: `messenger-flags-employee`
- App: Messenger 574.0.0, build 1035554267
- Bundle/executable: `com.facebook.Messenger` / `Messenger`
- `Messenger(1).ipa` SHA-256:
  `bc539c8b3031696ba6ff13f28b4b983eb3b03836bc2822347f8b17d7a8d59c0a`
- `FBTweaks-flags.zip` SHA-256:
  `5f5abe4bc2589f31d59c332fa30e2ed30fe03db958685014930a8062a2f13ead`
- Main images inspected: `Messenger`, `LightSpeedCore`, and
  `LightSpeedEngine`
- `LightSpeedCore` UUID: `4C4C44E0-5555-3144-A13D-5473258409E7`

The two attached branches and the Mach-O images were inspected before the
implementation was changed. LIEF 1.0.0 decoded segments, bindings, chained
fixups, Objective-C metadata, and relocations. Capstone 5.0.7 validated the
arm64 call ABI and consumers. Raw `llvm-objdump` load commands and indirect
symbols were checked separately so the section classification did not depend
on one parser.

## How Employee works in the original `flags` branch

The original implementation is layered; it is not a single broad feature
gate:

1. **identity owners** return/store Employee on the current Facebook user or
   session (`FBUserPreferences`, `FBBugReportConfiguration`, `RCDMobileConfigParams`);
2. **identity propagators** receive that value (`FBLoom`, WebView, Rage Shake,
   participant/viewer configuration);
3. **final UI/plugin gates** expose Internal Settings and tools
   (`FBShouldEnableInternalSettings`, EasyGating, explicit configuration setters).

Each Objective-C method has a validated encoding and its own original IMP.
Imported C functions are rebound through their GOT entry. The preference is
cached away from hot paths and unmatched calls always delegate unchanged.

## Messenger equivalents — and non-equivalents

The Facebook identity classes cannot simply be copied into Messenger 574:
`FBUserPreferences`, `FBBugReportConfiguration`, `RCDMobileConfigParams`,
`FBLoom`, `FBIdentitySwitcherGatingHelper`, and
`FFDBInternalSettingsWebViewController` are absent from the Messenger runtime
image.

The mapped Messenger chain is:

| `flags` role | Messenger 574 equivalent | Validation |
|---|---|---|
| current identity | `fb_ford.is_employee` | packed descriptor `0x008103fe000b1472` |
| final Internal plugin gate | `LSShouldEnablePluginBasedOnMobileConfigParam` | imported by `LightSpeedCore`; arm64 ABI mapped below |
| Internal Settings permission | `fb_ford.can_access_internal_settings` | packed descriptor `0x008103fe00051470` |
| participant propagation retained from `flags` | `MBUISimpleParticipantModel -isEmployee` | `B16@0:8` |
| web propagation | `FBWKWebView` and `FBWKWebViewDelegateAdaptor -setIsEmployee:` | `v20@0:8B16` |
| Rage Shake propagation | `LSRageShakeView` initializer's `isEmployee` argument | full 18-argument encoding checked exactly |
| Bloks Lab propagation | `BKBloksLabDeeplinkHelper` class method's `isEmployee` argument | `v60@0:8@16@24B32B36B40@44@?52` |
| broad internal gate | `EasyGatingGetBoolean_Internal_DoNotUseOrMock` | all four x-register arguments preserved |

Five other `-isEmployee` methods found in Messenger belong to contacts or
other participants: `MBQPreviewParticipant`, `MSGParticipantContact`,
`MSGMentionPlaceholderParticipant`, `MSGPublicChatParticipantAdapter`, and
`MSGPublicChatMemberAdapter`. They are not used as the current identity and are
not hooked. `MBUISimpleParticipantModel` is retained only because it is an
explicit downstream propagation point in the original `flags` branch; it is
not treated as the identity source.

The earlier mapping of `MSGEBDebugSettingsViewController` and
`MSGEBDebugUserSettingsOverrideViewController` was also removed. Those classes
are Encrypted Backups debug UI, not the Messenger Internal Settings/Tools
providers.

## Mach-O import evidence and fishhook correction

`LightSpeedCore` contains `LC_DYLD_CHAINED_FIXUPS`, but its import section is
not `S_REGULAR`. The raw section command is:

```text
sectname __got
segname  __DATA_CONST
addr     0x6298000
size     0x23550
type     S_NON_LAZY_SYMBOL_POINTERS
reserved1 0
```

`LC_DYSYMTAB` has an indirect symbol table, and the relevant slots resolve to:

```text
0x62988d0  _MSGCSessionedMobileConfigGetBoolean
0x629a478  _LSShouldEnablePluginBasedOnMobileConfigParam
0x629db30  _EasyGatingGetBoolean_Internal_DoNotUseOrMock
```

Therefore upstream fishhook does traverse this Messenger section. The earlier
claim that fishhook skipped an `S_REGULAR` `__got` was incorrect; the no-effect
bug was in identity coverage/ABI, not in section enumeration. Hard-coded slot
patching and UUID-specific `vm_protect` code were removed.

The vendored fishhook now includes the `__AUTH_CONST` and authenticated-GOT
support from `opa334/fishhook` commit
`4e468574a9e579214e9c92ea0e9ce1808be2a976`, with explicit
`__has_feature(ptrauth_calls)` guards. Messenger 574 itself uses the non-auth
`__DATA_CONST.__got` path, while the update keeps the source usable for future
PAC images.

No `MSHookFunction` or inline `__TEXT` mutation is used.

## Validated C ABIs

### Sessioned MobileConfig reader

At the mapped `LightSpeedCore` call sites, `x1` is a pointer to a 32-byte
descriptor, not the packed key itself:

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

The old `uint64_t x1` declaration compared a temporary stack address with the
packed keys, so every requested override missed. The current replacement reads
`parameter->rawValue` at `+16` and forwards the original pointer and arguments
for all unmatched keys.

### Final plugin gate and `is_employee`

Capstone disassembly of
`LightSpeedEngine+0x1A5CE0` (`LSShouldEnablePluginBasedOnMobileConfigParam`)
shows:

```text
x0 = MCI auth-data context
x1 = address of tagged descriptor pointer
bit 0 of *x1 = fallback BOOL
(*x1 & ~1) = address of 32-byte MobileConfig descriptor
descriptor + 16 = packed key
w0 = BOOL result
```

The implementation decodes that tagged pointer and checks the exact packed
key. When Employee/Internal Settings is active, the helper therefore returns
true at the plugin eligibility decision for `fb_ford.is_employee` and
`fb_ford.can_access_internal_settings`. This is the Messenger equivalent of
hooking the original branch's `FBShouldEnableInternalSettings`; it is not just
a generic MobileConfig fallback.

Internal Settings implies Employee in both persisted menu state and the atomic
runtime cache. Internal Tools implies both. Thus a stale preference combination
cannot enable the Internal section while leaving `is_employee` false.

### Objective-C MobileConfig readers

Some reads are dispatched through the exact managers below. Their declared
methods and encodings were checked in the 574 metadata and remain hooked with
one original IMP per class/method pair:

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

Only methods declared directly on each target class are installed. This detail
prevents the superclass/subclass recursion seen in the old build.

## 1.1.116 crash validation

The attached crash and package were analyzed together:

- crash SHA-256:
  `5dc7aafb6e05d8ddf2ab74e768228be3c60524440f995cfba23ae7670d292d5c`;
- package SHA-256:
  `b687e5ce589a33105453bfb5ac1e4445e89603d18e20e94e55a495e7ef74b373`;
- extracted dylib SHA-256:
  `f5d30247bbaaf85e0c6d7f6f7f4a0c9bde51bb01e0875768e530c5ff6d713df5`;
- crash and dylib UUID:
  `5717E1D5-741D-3024-B0D7-131E9ED3394D`.

The fault is a main-thread stack overflow, not a code-signing failure:
`EXC_BAD_ACCESS` hits the stack guard after 21,315 frames, with a recorded
recursion depth of 10,647. The repeating dylib offsets are `+0xB7E8` and
`+0xB804`; `+0xB804` follows an indirect call through a descriptor's stored
original IMP.

The old shared receiver-based replacement could enter the base-class hook via
`objc_msgSendSuper2` while retaining a subclass instance as `self`. It then
selected the subclass trampoline again and recursively recreated the same
call. The current implementation uses ten distinct replacements and ten
distinct original storage slots, plus separate originals for every identity
propagator. No hook selects an original trampoline from the runtime class of
its receiver.

## Final package and dylib validation

The final rootless package was rebuilt from a clean Theos object directory and
then extracted again for an exact payload comparison:

- package: `com.darthplagueiswise.fbtweak.messenger_1.1.0_iphoneos-arm64.deb`;
- package SHA-256:
  `cbc0a5fbe0d8a28769aefe585068682f7715136d973dbc6ec1d4aabdd00254a7`;
- packaged dylib SHA-256:
  `67316d34cd2e6c726eb182ff4ac0efa0eba0da2e250ffa23ab434098fb12f5fb`;
- packaged dylib UUID: `1149318A-9A7A-34EB-B2A4-563599DAD4C6`.

The staged and re-extracted dylibs have the same SHA-256. LIEF reports a code
signature and the CydiaSubstrate dependency. `llvm-nm` reports
`_MSHookMessageEx` as the only `MSHook*` undefined symbol; the dylib contains no
`MSHookFunction` import.

Capstone inspection of the packaged dylib confirms the compiled ABIs:

- `+0x77FC` tests `x1`, and `+0x7800` loads the MobileConfig key from
  `[x1, #0x10]`;
- `+0x7878` loads the tagged descriptor pointer, `+0x787C` clears bit 0, and
  `+0x7884` loads the plugin key from `[x8, #0x10]`;
- the EasyGating fall-through at `+0x7900` tail-branches through the original
  pointer without replacing `x0`–`x3`;
- the WebView setter replacements at `+0x85E4` and `+0x8608` load different
  original slots (`+0x10EF0` and `+0x10EF8`);
- representative context, sessionless, and user-session MobileConfig readers
  likewise load different original slots (`+0x10E98`, `+0x10EC8`, and
  `+0x10ED8`).

## Packed keys

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

Messenger registers `messenger_internal_settings`, `mwa_internal_settings`,
`threads_internal_settings`, and the native Settings section identifier
`msg_settings_internal_settings_section`. Those strings identify plugin/section
entries; they are not themselves BOOL selectors and are not hooked by name.

Messenger 574 has no standalone local Household membership BOOL. Household
therefore enables Homebase plus the verified mailbox/thread-settings gates.
Account membership, remote data, and mutations remain server-controlled.

## Native iOS 26 menu

The tab host is
`_TtC25MDSModernTabBarController25MDSModernTabBarController -viewDidAppear:`
with encoding `v20@0:8B16`.

The host attaches a native `UIContextMenuInteraction` to the tab bar and, when
identified by exact accessor/accessibility/geometry checks, the Messenger
logo/wordmark. `UITargetedPreview` uses the existing compact view under the
press. UIKit owns the iOS 26 Liquid Glass presentation and morph. The tweak
creates no custom glass view, fade panel, or synthetic preview capsule.

## Boundaries

- Disabled switches always return the original Messenger value.
- Employee/Internal are local client presentation and plugin gates only.
- No employee token, backend entitlement, household membership, or server data
  is fabricated.
- User-scoped plugins and tab models can be launch-cached; reopen Messenger
  after changing these flags.
- Packed keys and ABIs are specific to Messenger 574 and must be remapped for a
  different build.
