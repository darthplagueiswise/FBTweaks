# Liquid Glass UI: findings and design

Base: 30bce82e35b00165fc26372cc9b10e2eea873036. Scope: visual UI and layout; retain backend actions and existing test coverage. No comment cleanup or test pruning.

## Findings recorded before implementation

- Search styling clears the native text-field surface and geometry even though active screens use standard navigation search without the custom glass container.
- LocalConfig is a UITableViewController: configuring its view as opaque, then clearing its scroll view, makes the same root view transparent.
- Names Diagnostics, Live Trace, Network Inspector and the legacy browsers do not consistently apply table, cell, search and per-item navigation appearance.
- Scroll styling erases table.backgroundView, which is also owned by the Live Trace empty-state UI.
- Runtime detail sets navigation styling twice, uses a separate translucent cell fill, and does not reset action text colors on reused ordinary rows.
- Symbols filter header uses a fixed 92-point height and never refits to width or content-size changes. Its search presentation context is unspecified.
- Network detail puts four segments in navigation title space shared with Back and Export.
- The styling helper contains an unused parallel hierarchy of glass panels, custom cells, section headers, toolbars, search containers and collection/button decorators.

## Unified design

- UIKit owns native navigation/search/control materials. Scope navigation appearance to each screen's UINavigationItem; never restyle the host's shared bars.
- One UITableViewController base owns common table, search, navigation, automatic row height and cell background lifecycle. Keep screen-specific data/actions/timers in their screens.
- Shared table configuration owns an opaque grouped content surface and preserves backgroundView. Independent UIView controllers apply the same helpers to their own tables.
- Keep standard search field and segmented-control rendering; set semantic tints/text only. Remove unused alternate glass rendering APIs and types after checking all callers.
- Content overview is a semantic grouped panel, not another glass control layer.
- Fit Auto Layout table headers on layout and Dynamic Type changes. Move network segments into the content layout with safe-area constraints.
- Reset reused runtime detail text color before applying row-specific action colors.

## Verification plan

Run the full existing Python suite and source/build checks. Add focused native UIKit regression coverage for search, background ownership, repeated styling and fitted filter headers; retain existing chrome-isolation, selection and Dynamic Type checks. Native simulator/build requires macOS; enable the current PR target in the existing macOS workflow so this change can receive native validation.

## Native control grouping

- Live Trace previously put Capturar plus three text actions beside Back in one navigation bar. Move capture into an intrinsically sized header, label the switch for VoiceOver, and group Exportar/Limpar in an SF Symbol menu with a destructive Clear role; retain Refresh as a separate system action.
- Existing subgroup generation places all settings into generic Controls/Menus/Tools sections. Replace that layer with domain sections sourced from the same canonical row catalog: local identity versus instrumentation, runtime readings versus session probes, native controllers by area, and distinct Liquid Glass/tab bar/Dating/Beta sections. Keep every existing key, destination and action reachable once per subgroup.
- Keep semantic system colors and existing root SF Symbols, so grouped content follows the active native light/dark appearance.

## Native search and appearance

- iOS 26+: use UINavigationItemSearchBarPlacementIntegratedButton with hidesSearchBarWhenScrolling. UIKit owns the collapsed button, expanded field, menu presentation and material transitions. Earlier supported iOS versions keep their standard navigation search. No custom morph or layered blur is installed.
- All content/selection/tint colors use semantic UIKit colors, including the shared primary color. The overview title no longer duplicates the navigation title. Removed stale root footers after grouping by domain.
- Added real-UIKit regression cases for shared controller lifecycle, opaque grouped surfaces, preserved empty state, native search surface and expansion/collapse, dark-mode adaptation and Auto Layout filter header resizing. Existing chrome, selection and accessibility-header cases remain. The source-wiring assertion and preflight validator now follow the shared base rather than retaining an otherwise redundant wrapper.

Apple API references: [native search placement](https://developer.apple.com/documentation/uikit/uinavigationitem/searchbarplacement-swift.enum/integratedbutton), [integrated search](https://developer.apple.com/documentation/uikit/uinavigationitem/searchcontroller), [Liquid Glass adoption](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

## Local validation

- Existing Python suite: 81 tests run, 3 skipped, no failures.
- Python runner compilation, shell syntax and git diff --check pass.
- Native runner attempted on Linux; exit 2 explicitly reports unavailable macOS/Xcode/iOS 26+ Simulator. This is an infrastructure limitation, not a passing visual test.
- Existing macOS workflow is enabled for PRs against fix/mobileconfig-path-and-diagnostics so the native build and simulator checks can run on this PR.

## Follow-up from native CI 44012129230

The real iOS 26.5/iPhone 11 run compiled the production helper/base and passed 20 of 21 checks, including native chrome isolation, grouped/empty surfaces, Dark Mode, selection and header sizing. `search.native_activation` failed. The evidence showed search integrated into a bottom toolbar despite the preferred navigation placement; the test also sampled the wrapper view at an arbitrary 250 ms.

- Disable `searchBarPlacementAllowsToolbarIntegration` on iOS 26+ to keep collapsible search owned by the navigation item. Apple documents toolbar integration as enabled by default.
- Observe `didPresentSearchController:` and `didDismissSearchController:` instead of sampling by delay. Retain the weak delegate's observer until dismissal; inspect the actual text field window and visible bounds, not its wrapper. Record actual placement and visibility for diagnosis. The existing host watchdog still detects missing callbacks.
- This retains the failing behavior assertion; no test is skipped or weakened to accept activation alone.

## Rootless build delivery

Native UIKit checks remain mandatory before **publishing** the rootless package. Unit/static checks and the rootless compiler/package verifier now run before the two Simulator phases, so a CoreSimulator infrastructure failure cannot hide compiler diagnostics. Publication still depends on both native UI phases passing. It stamps the control Version as `1.0.<run_number>`, removes only previously generated `packages/*.deb`, requires exactly one fresh output and invokes `bash build.sh rootless`. The package verifier checks the expected Version as well as its existing `iphoneos-arm64`, `/var/jb`, source-commit, bundle and Mach-O contracts.

Artifacts are named `FBTweak-rootless-arm64-<run_number>` and contain the `.deb`, SHA-256 checksum and a JSON provenance manifest. The Actions summary repeats version, architecture, commit and hash. A failed test or package validation prevents publishing the installable artifact.

## Xcode 27 / CoreSimulator compatibility (2026-11-17)

The Theos target and SDK use iOS 27.1, on the GitHub-hosted `xcode-27` runner. In native CI, simctl accepted an iOS 27.2 generic runtime with an iPhone 18 Pro Max; iOS 27.1 with iPhone 15 Pro Max and iPhone 18 Pro Max was rejected by CoreSimulator (error 403), despite permissive device-type metadata. Both real-UIKit cases use the *observed working* runtime/device pair, and have a 300-second command/boot limit to accommodate first-boot costs. All original behavioral assertions remain enabled, and the verified rootless .deb is published only after they pass.
