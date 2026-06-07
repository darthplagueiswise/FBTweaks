# FBTweaks v5 hook and UI correction

## What was wrong in v4

- UI was forced to pure black surfaces. This made the hierarchy flat and did not follow the LiquidGlass container model.
- Cells used a heavy opaque custom background and lost readable hierarchy. The row label also looked too bold/heavy.
- Startup bootstrap installed persisted hooks from a constructor. That can make Facebook launch slower because it touches runtime/prefs before the app settles.
- MobileConfig native hooks used fishhook-style rebinding. That is not reliable for locally-defined C++ functions inside FBSharedFramework.
- MobileConfig ObjC scan used `objc_getClassList`, then filtered by class/image strings. That can scan too much and make the app/menu feel slow.
- MC handlers called original first and only then applied override. That lets original code/cache/side-effects run before the forced value.

## What v5 changes

- Runtime bootstrap has no constructor and does no replay/scan at launch.
- Native C++ bridges now use Substrate `MSHookFunction` + `MSFindSymbol`/`dlsym` for:
  - `__ZN12mobileconfig14getBoolDefaultEy`
  - `__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc`
- ObjC MobileConfig scanning now uses exact loaded Mach-O images through `_dyld_image_count` + `objc_copyClassNamesForImage`.
- Hook handlers check persisted override first. If forced value exists, the original getter is not called.
- Original IMP lookup walks the receiver class chain instead of using a dangerous selector-only fallback.
- UI uses adaptive system colors and attempts real UIKit 26 glass classes (`UIGlassEffect` / `UILiquidGlassEffect`) plus container background style. It no longer forces flat `UIColor.blackColor`.
- Rows use compact custom labels with regular font, readable metadata, and switch alignment. No default list truncation and no heavy icon column.

## Binary validation notes

Using `lief` and `capstone` in the analysis container confirmed the relevant native symbol strings are present in the supplied Facebook binaries:

- `Facebook(6)` contains MobileConfig symbols and selector names including `getBool:`, `getBoolWithoutLogging:`, `boolForParameter:withDefault:` and `__ZN12mobileconfig14getBoolDefaultEy`.
- `FBSharedFramework(106)` contains `__ZN12mobileconfig14getBoolDefaultEy`, `__ZNK4iglu9filterkit12ParameterMap7getBoolEPKc`, `getBool:withDefault:`, `getBool:withOptions:` and related ObjC selectors.

That is why v5 uses `MSHookFunction` for native C++ symbols and `MSHookMessageEx` only for ObjC method receivers.
