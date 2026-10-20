# Research: safe Objective-C runtime hooks in sideloaded social-media apps

Date: 2026-10-20. Applies to the `flags` branch, tested statically against the FBTweak source and the iOS 27 / Facebook 567 crash report. This is **not** a claim of an iPhone runtime fix.

## Verified comparable projects

- [Facebook No Ads](https://github.com/haoict/facebook-no-ads): older Facebook-specific tweak using named, feature-scoped Logos groups. Archived in 2023 and targeted older iOS/Facebook; does not establish compatibility with Facebook 567/583 or iOS 27.
- [SCInsta](https://github.com/SoCuul/SCInsta): injected Instagram tweak, separate build for `sideload` vs `rootless`. Sideload script packages `SCInsta.dylib` and separate FLEXing/libflex libraries.
- [BHTwitter](https://github.com/BandarHL/BHTwitter): independent `--sideloaded`, `--trollstore`, and `--rootless` paths, with distinct sideload injection and keychain-fix packaging.
- [PrisonFLEX](https://github.com/Uraniumm/PrisonFLEX): a FLEX loader made for jailed/sideloaded apps. It uses a known `UIWindow` lifecycle method and a three-finger gesture to open FLEX on demand; not an arbitrary replay of hundreds of saved IMP hooks.
- [FLEX](https://github.com/FLEXTool/FLEX): in-process runtime inspector with view/object/property/NSUserDefaults browsing and supported network inspection. Its networking views cannot, by themselves, prove complete C++ Tigon callback coverage.

Authoritative references: [Substrate MSHookMessageEx](https://www.cydiasubstrate.com/api/c/MSHookMessageEx/), [Apple class_copyMethodList](https://developer.apple.com/documentation/objectivec/class_copymethodlist(_:_:)), [Apple Launch Time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time), [Theos Logos](https://theos.dev/docs/logos-syntax).

## Crash evidence (user-provided IPS)

`Facebook-2026-10-19-235107.ips`: SIGABRT, thread 0, abort_report_np inside `dyld4::Loader::findAndRunAllInitializers`, about 130 ms from process launch. FBTweak build 204 UUID `85856fbf-c221-3687-bb3c-e663b6158ca3` matched extracted dylib. Other injected libraries were present. **The IPS does not name the faulty selector or identify a specific FBTweak hook frame.** It cannot prove which initializer caused the abort.

## Proven architectural hazards in FBTweak 204

1. `FBTRuntimeBoolReinstallPersistedHooks` and `FBTSymbolBrowserEngine reinstallPersistedHooks` ran from `%ctor` if the browser toggle was enabled. They can execute a user-saved `MSHookMessageEx` while dyld initializers are still running.
2. `source=observe` saved an actual hook for automatic replay even though it merely records a getter return. This can re-trigger a startup crash after selecting an unsafe target.
3. The two runtime browsers had independent `installed` registries and could install competing trampolines on the same class/selector.
4. `class_getInstanceMethod` accepts inherited methods. A persisted target can be stale or inherited after an IPA version change. The browser's on-demand enumeration used `class_copyMethodList` (own methods), but restoration did not enforce the same restriction.

## Change implemented in flags

- **No runtime browser auto-install from the dyld constructor**. Explicit, post-UI callback restores persisted force overrides after a one-second defer.
- Passive `source=observe` choices are kept in preferences for discovery but **never auto-rearmed after restart**. User must explicitly select observation again in the UI; observed event samples remain in-memory and are lost on process exit.
- Reject installing a runtime hook if a different runtime browser already owns that exact key; use an exact class/selector/class-method identity.
- Reject an inherited method at installation by checking the class's own `class_copyMethodList`.
- Do not add a second dynamic hook for known `FBUserPreferences.isEmployee` and `FBUser.isEmployee` selectors; route debugging through known Employee diagnostics.
- Existing force override values remain saved. Their effective behavior is pending until a post-UI restoration succeeds.

## Testing and remaining risks

- Portable contract tests check startup staging, passive hook recovery, and collision protection, and iOS/Theos CI compiles the full dylib.
- A preflight test and a successful CI build **do not verify runtime hook chains** on iOS 27. Substrate, the host IPA, and other injected dylibs can still cause a different crash.
- The next device experiment is a controlled A/B: identical signed IPA and dependencies, new FBTweak vs build 204, compare crashes and use the exact selector only after UI is stable. Do not simultaneously switch Facebook app version.
- The reported server `OAuthException #100` is unrelated to this SIGABRT and cannot be fixed by hook installation order.

## Separate optional tool

FLEX or PrisonFLEX can provide on-demand in-app inspection. Prefer as a separate debug build to avoid adding more injected initializers to the normal tweak. Before adoption: compile for target iOS/arm64, test against the actual sideloaded IPA and review dependency/license requirements. Do **not** inject Frida Gadget as a prerequisite.
