# V8 hook fix analysis

## What was wrong

The previous MobileConfig hook still accepted generic `Q`/`I` arguments as if they were MobileConfig param structs. That caused two problems:

1. Real `FBMobileConfigSessionlessContextManager`, `FBMobileConfigUserSessionContextManager`, and `FBMobileConfigAdminIDContextManager` methods were missed because their encodings are `mc_sessionless_bool_param_t`, `mc_sessionbased_bool_param_t`, and `mc_adminID_bool_param_t`, not only `mc_bool_param_t`.
2. Unrelated BOOL methods that took a plain integer could be hooked accidentally. That is a crash vector.

The executable/FBShared runtime hook used `MSHookMessageEx` for no-arg BOOL getters. For the runtime browser rows, a safer and more deterministic strategy is to patch the exact owner method implementation returned by `class_copyMethodList`, using `method_setImplementation` and an `imp_implementationWithBlock` trampoline. That mirrors the Ryuk-style exact class+selector model: no selector-wide original confusion, no class-chain ambiguity.

## Binary analysis actually performed

Tools used locally in the container:

- `lief 0.17.6`
- `capstone 5.0.7`
- custom ObjC metadata parser for `__objc_classlist`, `__objc_const`, method lists, and type encodings

Binaries analyzed:

- `/mnt/data/Facebook(6)`
- `/mnt/data/FBSharedFramework(106)`

Results:

- `Facebook(6)`: 47,232 ObjC classes, 7 methods with `*_bool_param_t` encodings, ~20,366 no-arg BOOL methods.
- `FBSharedFramework(106)`: 8,422 ObjC classes, 23 methods with `*_bool_param_t` encodings, ~894 no-arg BOOL methods.

Confirmed MobileConfig BOOL getter owners in `FBSharedFramework(106)`:

- `FBMobileConfigContextManager`
- `FBMobileConfigContextObjcImpl`
- `FBMobileConfigSessionlessContextManager`
- `FBMobileConfigUserSessionContextManager`
- `FBMobileConfigAdminIDContextManager`
- `FBMobileConfigStartupConfigs`

Confirmed type encodings include:

```objc
B24@0:8{mc_bool_param_t=Q}16
B28@0:8{mc_bool_param_t=Q}16B24
B32@0:8{mc_bool_param_t=Q}16@24
B36@0:8{mc_bool_param_t=Q}16@24B32
B24@0:8{mc_sessionless_bool_param_t=Q}16
B32@0:8{mc_sessionless_bool_param_t=Q}16@24
B24@0:8{mc_sessionbased_bool_param_t=Q}16
B32@0:8{mc_sessionbased_bool_param_t=Q}16@24
B24@0:8{mc_adminID_bool_param_t=Q}16
B32@0:8{mc_adminID_bool_param_t=Q}16@24
```

## V8 changes

### MobileConfig

- Hooks only exact `*_bool_param_t` method encodings.
- Accepts `mc_bool_param_t`, `mc_sessionbased_bool_param_t`, `mc_sessionless_bool_param_t`, and `mc_adminID_bool_param_t`.
- No longer treats plain `Q`/`I` as MobileConfig bool params.
- Hooks retry if classes are not loaded yet; it does not mark install as complete with zero records.
- Override check happens before original call.

### Executable / FBShared Bool Runtime

- Scanner stays image-specific: `objc_copyClassNamesForImage`.
- Hooking switched to exact owner `method_setImplementation` with `imp_implementationWithBlock`.
- Original IMP is keyed by `+/- Class#selector`.
- Persisted overrides use a v3 key namespace, with v2 fallback migration.

## Why no fishhook for these rows

Fishhook is useful for rebinding imported lazy/non-lazy symbol pointers in Mach-O sections. The no-arg Objective-C runtime rows are not imported C symbols; they are Objective-C method IMPs. For those, exact method replacement is the correct target.
