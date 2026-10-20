# QE-info diagnostic crash containment — 2026-10-20

## Reproduced source-level cause of the broad interception surface

The existing **Log de fetch QE-info** toggle did more than enable logging. It invoked `FBTMobileConfigResponseCaptureInstall()` which installed *all* these systems as a side effect:
- process-wide `NSURLSession dataTaskWithRequest:completionHandler:` interception, including enumerated subclasses;
- C++ Tigon forwarding callback fishhooks and UUID-specific `__DATA_CONST` / vtable pointer replacements;
- native `FBMobileConfigTigonFetcher::asyncFetch` data-slot substitution with C++ callback ownership, plus an internal `isEmployee` reader hook;
- `FBMobileConfigQEInfoManager::fetchQEInfoSynchronously` and `refreshNames` C++ import rebinding;
- global `NSError initWithDomain:code:userInfo:` and `UIAlertController` factory hooks.

The Tigon data slot rebindings are pinned to **specific image UUIDs and 583-era layouts**. Correct UUID matching protects against some ABI mismatches, but does **not prove** that no other injected binary or runtime subtype changes callback ownership or ABI. Intercepting all NSURLSession subclasses and NSError also broadens the hooking surface far outside QE.

The user reports a QE-logging-associated crash. There is **no new crash IPS attached to this turn**, so no specific frame can yet be definitively assigned to one of the above installations.

## Release containment

Ordinary sideloaded FBTweak builds define `FBT_ENABLE_QE_INVASIVE_HOOKS=0` (default in `FBTMobileConfigFetchDiagnostics.h`). A single predicate `FBTQEInvasiveHooksAllowed()` guards all seven deep install entry points. It prevents these hooks from installing even when an existing QE diagnostic preference is still enabled from a previous version. This is also validated by CI.

**QE UI logging remains available**: selection request events, config/param names, native QE failure alert metadata and internal query-context observations from already-installed, ABI-checked native UI hooks. It does not claim to supply original HTTP response bodies, OAuth header context, native Tigon transport callbacks, or wire status. QE-info backend refusal remains unaffected.

The global error and alert hooks are disabled by default too. A targeted lab build may separately enable deep instrumentation after ABI and sideload lifecycle validation; do not enable it in a normal release build or present it as a harmless toggle.

## Tests and deployment

```sh
python3 -m unittest discover -s tests -p 'test_qe_safe_diagnostics.py' -v
```

The CI also rejects `FBT_ENABLE_QE_INVASIVE_HOOKS=1` configured in the normal build scripts.

**Not yet proven:** stable cold-start and QE navigation on iOS 27, Facebook 567 or 583; a passing Theos CI is not an iPhone runtime confirmation. Existing invasive patches from older dylib processes cannot be undone without fully terminating and restarting the app using the newly injected dylib, preferably from a clean (not already-injected) IPA.
