# FBTweaks compact UI/actions patch

Changes:

- Compact text for large feature names: title 9.5pt, detail 7.25pt.
- Compact neutral switches using `FBGRConfigureCompactSwitch`.
- Search button added to MC category, MC runtime and BOOL runtime screens.
- Apply hooks button added to MC category, MC runtime, BOOL runtime and root surface.
- Restart button added to MC category, MC runtime, BOOL runtime and root surface.
- Root now exposes Apply and Restart on the navigation bar and as actions.
- Keeps WATweaks-style persisted startup: safe known-class MC reapply, full MC scan only on explicit Apply.
