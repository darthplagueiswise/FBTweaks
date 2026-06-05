# FBTweaks real runtime rebuild

This build removes the old fake LiquidGlass MobileConfig category and uses the live ReactMobileConfigMetadata catalog as the source of truth.

Catalog priority:
1. `NSBundle.mainBundle.bundlePath/ReactMobileConfigMetadata.json` inside Facebook.app.
2. The explicit tested path under `/private/var/containers/Bundle/Application/.../Facebook.app/ReactMobileConfigMetadata.json`.
3. App data container override locations under Documents/FBTweaks, Library/Application Support/FBTweaks, Caches/FBTweaks and tmp/FBTweaks.
4. Rootless app-support paths and embedded resources.

The menu theme tries only real UIKit Liquid Glass classes (`UIGlassEffect`, private glass variants if present). It does not use `UIBlurEffect` and does not simulate blur.
