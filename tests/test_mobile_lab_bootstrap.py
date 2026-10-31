#!/usr/bin/env python3
"""Contract tests for launch-latched Mobile Lab environment configuration."""
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def load(path):
    return (ROOT / path).read_text(encoding="utf-8")
class MobileLabBootstrapTests(unittest.TestCase):
    def test_default_on(self):
        self.assertIn("extern NSString * const FBTKeyMobileLabEnabled;", load("src/FBTDefaults.h"))
        prefs = load("src/FBTDefaults.m")
        self.assertIn('FBTKeyMobileLabEnabled      = @"fbt_mobile_lab_enabled"', prefs)
        self.assertIn("FBTKeyMobileLabEnabled:                 @(YES)", prefs)
    def test_startup_before_hooks(self):
        src = load("src/Tweak.x")
        ctor = src.split("%ctor {", 1)[1]
        self.assertLess(ctor.index("[FBTDefaults registerDefaultsOnce];"), ctor.index("FBTConfigureMobileLabEnvironment();"))
        self.assertLess(ctor.index("FBTConfigureMobileLabEnvironment();"), ctor.index("%init(FBTHost);"))
        fn = src.split("static void FBTConfigureMobileLabEnvironment(void) {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("FBTKeyMobileLabEnabled", fn)
        self.assertIn('setenv("LAB_IS_ACTIVE", "1", 0)', fn)
        for unsafe in ("unsetenv", "MSHookFunction", "MSHookMessageEx", "FBT_QE_LAB", "FBT_ENABLE_QE_INVASIVE_HOOKS", "fishhook"):
            self.assertNotIn(unsafe, fn)
    def test_ui_switch_is_restart_latched(self):
        ui = load("src/Settings/FBTSettingsViewController.m")
        self.assertIn('@"title": @"Mobile Lab no lançamento"', ui)
        self.assertIn('@"key": FBTKeyMobileLabEnabled, @"restart": @YES', ui)
    def test_existing_containment_stays(self):
        self.assertIn("#define FBT_ENABLE_QE_INVASIVE_HOOKS 0", load("src/Runtime/FBTMobileConfigFetchDiagnostics.h"))
        self.assertIn("FBTRuntimeBoolReinstallPersistedHooks();", load("src/Tweak.x"))
if __name__ == "__main__":
    unittest.main()
