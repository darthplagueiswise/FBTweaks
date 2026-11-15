# Liquid Glass and complete visual override groups

The previous build changed the shared navigation bar when opening a child
settings page. Returning to the root on iOS 26 kept that appearance. Cells also
mixed `selectedBackgroundView` and `backgroundConfiguration`, APIs that reset
one another. The overview header had a fixed height despite using Dynamic Type.

The settings pages now use system appearances on their own `UINavigationItem`,
one cell background configuration with automatic state updates, and a header
that measures its text at the current width and text size. Shared host navigation,
toolbar and tab-bar appearance is left to the host. The typed local editor uses
the same appearance helpers.

## Override coverage

Liquid Glass and Floating Tab Bar previously had manually selected BOOL-only
rows. They now select complete records from `FBTLocalConfigCatalog` for the same
configuration IDs and open the existing typed editor. The loader runs off the
main thread. Records from distinct maps/scopes remain separate, including RN.
Unknown names or types remain unknown; no packed descriptor is synthesized.

The supplied Facebook 587.0.0/build 1110946418 IPA maps contain:

| Group | Configuration ID | Parameters |
| --- | --- | --- |
| Liquid Glass | 102680 | 90 in admin map |
| Liquid Glass | 120162 | 8 in admin map |
| Liquid Glass | 125862 | 2 in primary map |
| Floating Tab Bar | 80843 | 93 in admin map, 9 occurrences in RN map |

Liquid Glass therefore exposes 100 mapped parameters rather than the previous
23 curated BOOL rows: 92 BOOL, 2 int64, 3 string and 3 double. These counts describe
the supplied maps, not every Facebook build. The installed app's own maps supply
the UI. The Floating Tab Bar page no longer fabricates controls for old indices
that are absent from those maps.

File writes are followed by numeric-ID readback before reporting success.
Persisting a file value does not prove that a particular startup object has
reloaded it. Native inspection still requires an actual matching compiled
descriptor, and unsupported readers remain explicitly unavailable.

## Disassembly reference and limits

The UI regression was checked against the actual shipped build 435 dylib from
commit `4a921517aab726724f86a74854736471cab9c31c`, SHA-256
`af1f36319455d5c67b57ba77a4d51b769777546b1b1f26fe61d1832151235ad9`.
REA/Ghidra 12.1.4 exported these `LC_FUNCTION_STARTS`-bounded ARM64 windows:

| Function | Start | End, exclusive | Bytes |
| --- | --- | --- | --- |
| Shared navigation styling | 0x4fa0 | 0x538c | 1004 |
| Root navigation default | 0xb89c | 0xb970 | 212 |
| Cell background helper | 0x69c8 | 0x6be8 | 544 |
| Base page appearance | 0x29878 | 0x298c8 | 80 |

All 1,840 bytes / 460 words were bound back to the original Mach-O. These are
derived raw-window dossiers: imported selectors, outlined helpers and global
data are absent. Ghidra's pseudocode warnings remain retained; source and the
original Mach-O provide the external context. This is not a claim of complete
Facebook disassembly or proven server behavior.

The local evidence directory is
`analysis_final/consistency-587/fbtweaks-ui-catalog-20261115/` in the analysis
workspace, outside this repository. Original inputs and the bundled names gzip
are preserved. `catalog-coverage.json` binds the map counts to 15 hashed inputs;
`verify_catalog_coverage.py --verify catalog-coverage.json` independently checks
the retained result. Its native v2/v4 comparisons cover coordinates and types;
the nine selected RN occurrences also match the admin v4 registry. This does
not turn RN slot identifiers into native packed descriptors.

## Verification

`tests/FeatureCatalogCoverageTests.m` executes the real feature selector against
fixtures with all four types, repeated config IDs in different scopes, unknown
metadata and absent configurations. It also checks that the legacy group is not
expanded by this change.

`scripts/test-uikit-simulator.py` builds a minimal UIKit host, without Facebook or
the injected dylib. CI runs it on iOS 26 or later against the previous helper and
the new helper. The baseline must reproduce a navigation or selection assertion
failure; a build, launch or Simulator failure is an infrastructure error. The new
helper must pass navigation isolation, automatic cell feedback and accessible
header layout checks. Reports and screenshots are retained in the workflow's
UIKit evidence artifact.

The full rootless build then runs the existing persistence and descriptor tests
and verifies the packaged paths, architecture, resources and source commit.
Simulator results cover the shared UIKit helper, not every Facebook screen or a
physical iPhone. They do not validate employee eligibility or remote downloads.

Apple references: [TN3106: navigation appearance](https://developer.apple.com/documentation/technotes/tn3106-customizing-uinavigationbar-appearance),
[per-item appearance](https://developer.apple.com/documentation/uikit/uinavigationitem/standardappearance),
[mutually exclusive cell background APIs](https://developer.apple.com/documentation/uikit/uitableviewcell/backgroundview).
