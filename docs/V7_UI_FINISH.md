# v7 UI finish

This pass is UI-only. It keeps the v6 exact MobileConfig hook strategy unchanged and replaces the menu presentation layer.

Changes:

- No flat pure-black background. Dark mode uses an elevated blue/graphite adaptive background.
- Rows use a glass card subview, not `UITableViewCell.backgroundView`, so reuse and Auto Layout are stable.
- Real SDK26 LiquidGlass lookup remains: `UIGlassEffect`, `UILiquidGlassEffect`, `_UIGlassEffect`, `_UILiquidGlassEffect`.
- Feature identifiers break after `:` to stop unreadable horizontal truncation.
- Runtime rows no longer waste space with large icons.
- Root/category/action rows keep small 30pt icon pills only where useful.
- Footers with long explanatory text were removed from runtime screens.
- Fonts are smaller, regular, and monospaced for feature keys.
- Switches are scaled to 84% and get required compression priority so labels remain readable.
