# FBTweaks Real Bool Runtime Browser

This is not ReactMobileConfig metadata browsing. It is a live ObjC runtime scanner.

## Two scanners

1. **Executable Bool Runtime — Facebook**
   - Filters classes by `class_getImageName(cls)` matching the current `NSBundle.mainBundle.executablePath` or `/Facebook.app/Facebook`.
   - This is the runtime view for ObjC classes/methods implemented by the main executable.

2. **FBSharedFramework Bool Runtime**
   - Filters classes by `class_getImageName(cls)` containing `/FBSharedFramework.framework/FBSharedFramework`.
   - This is the runtime view for ObjC classes/methods implemented by FBSharedFramework.

## Patchable criteria

A method appears in the browser only when all criteria match:

- It belongs to the selected image.
- It is an Objective-C instance method or class method.
- It has no user arguments (`method_getNumberOfArguments(method) == 2`).
- It returns a boolean-compatible encoding: `B`, `c`, or `C`.
- The selector is getter-like and has no colon.

## Hooking model

Rows are not hooked during launch. Hooking is on demand:

- Open a row.
- Choose `Force YES` or `Force NO`.
- FBTweaks installs `MSHookMessageEx` for that exact class/selector and stores a persistent override key.

Key format:

```text
Facebook|ClassName|-|selectorName
Facebook|ClassName|+|selectorName
FBSharedFramework|ClassName|-|selectorName
FBSharedFramework|ClassName|+|selectorName
```

This is intentionally separate from MobileConfig `slotId` overrides. MobileConfig remains slot-based; Bool Runtime is class/selector-based.

## Why this is real runtime

The list is not generated from the JSON catalog and not hardcoded from offline strings. It is built inside the app process using:

```objc
objc_copyClassList
class_getImageName
class_copyMethodList
method_getNumberOfArguments
method_copyReturnType
MSHookMessageEx
```

## ReactMobileConfigMetadata path

The MobileConfig browser still prioritizes the live JSON inside the app bundle:

```text
/private/var/containers/Bundle/Application/5C38EEAB-1818-4C68-BF7D-A13378A902C2/Facebook.app/ReactMobileConfigMetadata.json
```

The dynamic version is:

```objc
NSBundle.mainBundle.bundlePath/ReactMobileConfigMetadata.json
```
