# Catalog resource dependency refactor

Scope: resource lookup ownership only; catalog data, query parsing and public
FlagCatalog APIs preserve their behavior. No tests or comment cleanup.

## Problems and decision

- Place resource lookup below both catalogs in `FBTBundleResources`.
  - `FBTFlagCatalog.m` imports `FBTLocalConfigCatalog.h` to translate captured keys.
  - `FBTLocalConfigCatalog.m` imports `FBTFlagCatalog.h` solely to locate a bundled names file.
  - Catalog interpretation and filesystem resource resolution change for different reasons.
  - These two imports currently create a cycle without a data-model reason.

Keep the existing FlagCatalog resource methods as compatibility entry points,
backed by the resource resolver. LocalConfig uses the resolver directly.
The resource search order and fallback remain exactly the same: rootless,
rootful, embedded bundle, then main bundle for individual resources. No cache
is added; resource existence is still checked at lookup time.

## Build linkage

The Theos source discovery includes the new implementation automatically.
The standalone native descriptor test command must link the implementation
explicitly, just as it explicitly links the local catalog. Test sources remain
unchanged.
