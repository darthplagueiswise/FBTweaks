# Ryukgram replication notes for FBTweaks v4

Analyzed the supplied Ryukgram source zip and copied the working design principles rather than the Instagram-specific class names.

Key replication points:

- Runtime BOOL hooks use exact class + selector names and `imp_implementationWithBlock`, not a generic selector-only trampoline. This fixes wrong-original/wrong-class dispatch.
- Overrides are persisted in one dictionary (`fbgr.runtime.bool.overrides.v2`) and reinstalled at launch by a tiny bootstrap that does not scan the whole runtime.
- Runtime scanners enumerate classes from the selected Mach-O image with `objc_copyClassNamesForImage`, matching the Ryukgram `SCIGatingCatalog` approach.
- MobileConfig slot overrides are warmed from prefs and installed early only when overrides exist.
- UI rows are black compact rows with full wrapping names, no icon, no subtitle, regular text.

Binary validation performed with LIEF/capstone against the supplied Facebook and FBSharedFramework binaries:

- `FBSharedFramework(106)` exports `_OBJC_CLASS_$_FBMobileConfigContextManager`, `_OBJC_CLASS_$_FBMobileConfigSessionlessContextManager`, `_OBJC_CLASS_$_FBMobileConfigUserSessionContextManager`, `_OBJC_CLASS_$_METAIGLUFilterParameterMap`, `__ZN12mobileconfig14getBoolDefaultEy`, and `__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc`.
- Capstone disassembly confirmed the binaries are ARM64 Mach-O and parsable at `__text`.
- The Facebook main executable is stripped but has MobileConfig selector strings; FBSharedFramework carries the real MobileConfig symbols.
