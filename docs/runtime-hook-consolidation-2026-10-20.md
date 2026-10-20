# FBTweak — Runtime BOOL single-owner architecture

References: WATweaks dogfood2 (WAGRGateHooks / WAGRGateStore / cold-start validation) and YTABConfig agent/fix-sideload-black-screen (YTABRuntimeBrowser, cache, packaging).

## Implementation in flags

- `FBTRuntimeBoolBrowser` exclusively installs runtime BOOL hooks. `FBTSymbolBrowserEngine` now *only* discovers methods and delegates Force ON/OFF, installation status and observed values to the same registry; the engine cannot install a second trampoline.
- Legacy `fbt_symbol_overrides` NSNumber entries are imported once to `fbt_runtime_bool_overrides`; existing overrides take precedence. The migration marker is `fbt_symbol_overrides_migrated_v1`. The legacy dictionary is retained for rollback/backup.
- The runtime installer only accepts methods explicitly implemented on the selected class, with no explicit arguments and exact arm64 encodings `B16@0:8` or `c16@0:8`. The known employee selectors remain separately owned.
- Values in the Symbol Browser are now **observed values**, not speculative calls. The original getter runs only when Facebook naturally invokes it and the override mode allows pass-through.
- Only one persisted hook restoration call is made after the tab host appears, with directed retries; no global method scan is performed in the constructor.
- Native Live Trace is a lazily constructed C++ ring, not a static non-trivial global constructed in dyld startup. Its capture flag is initialized after the first host UI appearance.

## Binary and runtime validation

CI tests contracts and performs a Theos build; `verify_macho_installation.sh` checks the rootless .deb's architectures and load commands. A rootless `@rpath` binary is **not** automatically Feather-compatible; the injected IPA needs `@executable_path/Frameworks/FBTweak.dylib` when that is its actual injection location, matching LC_LOAD_DYLIB, valid Substrate rpaths, signatures and no existing duplicate FBTweak dylib.

**CI does not prove the reported iOS 27 SIGABRT is corrected.** The original IPS stack identifies dyld initializers but not a specific method, and ARM64 runtime validation on the signed, sideloaded app remains essential.
