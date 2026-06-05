# FBTweaks runtime persistence patch

Validated against uploaded Facebook(7), FBSharedFramework(110), and ReactMobileConfigMetadata(8).

- Facebook(7): arm64 Mach-O executable, minOS 15.1, SDK 26.2.
- FBSharedFramework(110): arm64 dylib, minOS 15.1, SDK 26.2.
- ReactMobileConfigMetadata(8): 5,377 schema entries, 4,679 boolValue parameters, slots 0...4678.

Core fixes:

1. MC slot overrides continue to use `fbgr.slot.<slotId>` but now hooks install automatically on launch when slot overrides exist.
2. Runtime BOOL overrides now persist hook specs through `fbgr.runtime.hook.index.v1`, not just the value key.
3. Runtime BOOL hooks reinstall on launch and delayed passes so classes loaded after startup still get patched.
4. Reset clears MC slots, runtime BOOL overrides, persisted hook index, and forced LiquidGlass prefs.
5. LiquidGlass UI uses dynamic `UIGlassEffect` and `UIGlassContainerEffect`, with true white/black background fallback for light/dark mode.
