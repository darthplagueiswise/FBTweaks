# Binary analysis notes

Analyzed local binaries supplied in the session:

- `Facebook(6)` — Mach-O 64-bit arm64 executable
- `FBSharedFramework(106)` — Mach-O 64-bit arm64 dylib

Tools used in container:

- `lief`
- `capstone`
- `file`
- `strings`

Relevant findings:

## Facebook executable

LIEF parsed the binary as `FILE_TYPE.EXECUTE`, CPU `ARM64`.

Relevant Objective-C / symbol strings found:

- `_OBJC_CLASS_$_FBMobileConfigAdminIDContextManager`
- `_OBJC_CLASS_$_FBMobileConfigContextManager`
- `_OBJC_CLASS_$_FBMobileConfigSessionlessContextManager`
- `_OBJC_CLASS_$_FBMobileConfigUserSessionContextManager`
- `getBool:`
- `getBool:withDefault:`
- `getBool:withOptions:`
- `getBool:withOptions:withDefault:`
- `getBoolWithoutLogging:`
- `getBoolForParam:withDefault:`
- `IGLiquidGlassNavigationExperimentHelper`

## FBSharedFramework

LIEF parsed the binary as `FILE_TYPE.DYLIB`, CPU `ARM64`.

Relevant strings/symbols found:

- `FBMobileConfigValueStore::getBoolData`
- `getBool:`
- `getBool:withDefault:`
- `getBool:withOptions:`
- `getBool:withOptions:withDefault:`
- `getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:`
- `getBoolWithoutLogging:`
- `getBoolWithoutLogging:withDefault:`
- `__ZN12mobileconfig14getBoolDefaultEy`
- `__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc`
- `_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper`
- `_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper`

## Hooking decision

The final hook strategy is:

1. `Tweak.x` does not install anything except the known working longpress menu entry.
2. MobileConfig hooks are installed on demand.
3. Objective-C selectors are hooked via `MSHookMessageEx`.
4. C/C++ boolean bridges are hooked via `fishhook`:
   - `__ZN12mobileconfig14getBoolDefaultEy`
   - `__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc`
5. Executable/FBShared runtime browsers scan loaded Objective-C classes by image path and install per-row `MSHookMessageEx` hooks only after the user toggles a row.
