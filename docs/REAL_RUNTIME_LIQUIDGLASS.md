# FBTweaks fresh SDK26 runtime

This rebuild keeps only the working exact Facebook tab-button longpress from the provided base. Everything else is rebuilt around SDK26.2, real UIKit LiquidGlass class lookup, real ReactMobileConfigMetadata parsing and real ObjC runtime bool scanning.

## Startup safety

Tweak.x does not install MobileConfig hooks, LiquidGlass hooks, DogFood presets, global UIWindow hooks or broad UIViewController hooks at startup. It only installs the exact tab button hooks needed to open the menu.

## Metadata source

The catalog tries Facebook.app/ReactMobileConfigMetadata.json first, including the observed path:

`/private/var/containers/Bundle/Application/5C38EEAB-1818-4C68-BF7D-A13378A902C2/Facebook.app/ReactMobileConfigMetadata.json`

It falls back to app container paths, rootless app-support resources and embedded gzip metadata.

## Real runtime browsers

MobileConfig Runtime Browser patches bool slots through getBool:withOptions hooks on validated MobileConfig owner classes.

Executable Bool Runtime and FBSharedFramework Bool Runtime scan loaded ObjC classes using class_getImageName, class_copyMethodList and method_copyReturnType, filter zero-argument BOOL methods and hook selected rows using MSHookMessageEx.
