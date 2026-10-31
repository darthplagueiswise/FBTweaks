#!/usr/bin/env python3
"""Portable contract tests; iOS ABI/runtime behavior still needs device validation."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


class RuntimeBoolContractTests(unittest.TestCase):
    def test_employee_owner_remains_known_logos_hook(self):
        source = text("src/Features/Employee/FBTEmployeeMode.x")
        self.assertIn("%hook FBUserPreferences", source)
        self.assertIn("- (BOOL)isEmployee", source)
        self.assertIn("- (void)setEmployee:(BOOL)value", source)
        self.assertIn("FBTKeyEmployeeEnabled", source)

    def test_no_duplicate_employee_sweep(self):
        ui = text("src/Settings/FBTSettingsViewController.m")
        runtime = text("src/Runtime/FBTRuntimeBoolBrowser.m")
        self.assertNotIn('@"Employee sweep runtime"', ui)
        self.assertNotIn('FBTRuntimeBoolInstallSweep(@"employee"', ui)
        self.assertNotIn('@"employee":', runtime)
        self.assertIn('@"dogfood":', runtime)
        self.assertIn('@"internaldebug":', runtime)

    def test_legacy_migration_is_scoped(self):
        boot = text("src/Tweak.x")
        runtime = text("src/Runtime/FBTRuntimeBoolBrowser.m")
        # The migration runs in %ctor, but automatic restoration now occurs
        # post-launch in viewDidAppear; source order no longer means run order.
        self.assertIn('FBTRuntimeBoolClearSweep(@"employee");', boot[boot.index('%ctor {'):])
        self.assertIn('FBTRuntimeBoolReinstallPersistedHooks();', boot[:boot.index('%ctor {')])
        self.assertIn('[entry[@"source"] isEqualToString:source]', runtime)
        self.assertIn('if (!changed) return;', runtime)

    def test_persist_first_and_retry_exact_targets(self):
        source = text("src/Runtime/FBTRuntimeBoolBrowser.m")
        start = source.index("static void FBTRuntimeBoolSetOverrideWithSource(")
        end = source.index("NSUInteger FBTRuntimeBoolInstallSweep", start)
        segment = source[start:end]
        self.assertLess(segment.index("[FBTDefaults setDict:all"), segment.index("FBTRuntimeBoolInstallOne("))
        self.assertIn("void FBTRuntimeBoolRetryPendingHooks(void)", source)
        retry = source[source.index("void FBTRuntimeBoolRetryPendingHooks(void)"):
                       source.index("// Discover methods by Objective-C type encoding")]
        self.assertIn("FBTRuntimeBoolReinstallPersistedHooks();", retry)
        self.assertNotIn("objc_getClassList", retry)

    def test_observe_return_without_reinvoking_original(self):
        source = text("src/Runtime/FBTRuntimeBoolBrowser.m")
        begin = source.index("IMP replacement = imp_implementationWithBlock")
        end = source.index("MSHookMessageEx(hookClass", begin)
        hot = source[begin:end]
        self.assertIn("__atomic_load_n(&captured->forceMode", hot)
        self.assertTrue("__atomic_add_fetch(&captured->invocationCount" in hot or "__atomic_fetch_add(&captured->invocationCount" in hot)
        self.assertLess(hot.index("if (mode != -1)"), hot.index("captured->orig ?"))
        self.assertNotIn("NSUserDefaults", hot)
        self.assertNotIn("FBTBoolOverrideForKey", hot)
        self.assertIn("observedOriginal", hot)
        self.assertIn("observedEffective", hot)

    def test_ui_distinguishes_installed_and_observed(self):
        runtime = text("src/Runtime/FBTRuntimeBoolBrowser.m")
        ui = text("src/Settings/FBTSettingsViewController.m")
        for field in ("hookInstalled", "installState", "observedOriginal", "observedEffective", "invocationCount"):
            self.assertIn(f'@"{field}"', runtime)
        for field in ("installState", "observedOriginal", "observedEffective", "invocationCount"):
            self.assertIn(f'e[@"{field}"]', ui)


if __name__ == "__main__":
    unittest.main()
