# Untangle decision log

Base: `fix/mobileconfig-path-and-diagnostics`, `bf98d0fe89582b0c17e5d1a4718f4db9fcb283d1`.
Scope: behavior-preserving refactoring; preserve existing comments and tests.

## UI findings and design

- Own whitespace tokenization and case-insensitive AND substring matching in a
  Foundation-only UI search module. Callers continue to build their own search
  fields and symbols continue to tokenize once for an entire result set.
  - Hidden link: `FBTSettingsViewController.m` has its own query tokenization and
    matching policy, duplicated by `queryTokens` and `entry:matchesTokens:` in
    `FBTSymbolsBrowserViewController.m`. A search-policy change needs both copies.
  - Preserve lowercasing, whitespace/newline boundaries, empty-token handling,
    order-independent substring matches, nil strings and empty-query behavior.
- Remove the unused `reduceTopInset` setting and its assignments.
  - Surplus: the base settings controller initializes it and the symbols browser
    changes it, but no code reads it; actual inset configuration is unconditional.
- Remove the unused custom-cell registration and reuse identifier.
  - Surplus: the base settings controller registers `kFBTBaseCustomCell`, but no
    caller dequeues it; custom rows supply their own cells through the provider.

## Preserved boundaries

- Keep existing controller-specific query fields, UI labels and hook actions.
- Keep existing comments and tests, including source-contract tests.
- Keep `FBTConfigureDefaultLiquidGlass` because existing source-contract tests
  reference its body; appearance behavior is outside this search refactor.

## Other reviewed boundaries and decisions

- [Build contract](untangle-build-decisions.md): one asset validator for source and installed bundles, with explicit policy.
- [Catalog resources](untangle-catalog-decisions.md): resource lookup no longer creates a catalog import cycle.
- [Shared utilities](untangle-utils-decisions.md): runtime callers no longer import Settings for preference helpers.
- Inspected src (98 files before changes), scripts, existing tests, build configuration and recent commit history. Runtime hook ordering, remote diagnostics, feature eligibility and transport behavior remain existing requirements; these were not redesigned in this pass. The large runtime/controller modules remain potential follow-up work, rather than being mechanically split without executable native coverage.

## Validation

- Existing Python suite: 81 tests, 3 skipped, no failures before or after changes.
- Existing navigation contracts: 4 pass.
- Shell syntax checks pass for all changed scripts.
- Asset validation passes for the real bundle in source and installed modes; temporary fixtures verify empty/missing assets and invalid options.
- Reviewed changed module boundaries independently; no concrete issue remains in those changes.
- Native Objective-C/Foundation, UIKit simulator and Theos build require macOS/iOS SDK and were not run on this Linux host. Descriptor CI compilation now links the extracted resource implementation.
- No test files edited; no comment-cleanup pass performed.
