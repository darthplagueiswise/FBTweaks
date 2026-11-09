"""Do not regress to a second dyld-time Logos initialization of Settings UI."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE = (ROOT / "src/Settings/FBTGateSettingsAugment.x").read_text(encoding="utf-8")
UI = (ROOT / "src/Settings/FBTSettingsViewController.m").read_text(encoding="utf-8")
MAIN = (ROOT / "src/Tweak.x").read_text(encoding="utf-8")


class SettingsDyldSafety(unittest.TestCase):
    def test_no_obsolete_settings_ctor_or_rebuild_hook(self):
        self.assertNotIn("%ctor {", GATE)
        self.assertNotIn("%hook FBTSettingsViewController", GATE)
        self.assertNotIn("%init(FBTGateSettingsAugment)", GATE)
        self.assertNotIn("sections[4]", GATE)
        self.assertNotIn("base.count < 5", GATE)

    def test_feature_install_is_explicitly_requested_by_the_user(self):
        self.assertIn("void FBTSettingsGateDidSwitch(NSString *key, BOOL enabled)", GATE)
        self.assertIn("FBTSettingsGateDidSwitch(sender.prefKey, sender.isOn)", UI)
        self.assertIn("FBTKeyMobileConfigNativeUIWarmupEnabled", UI)

    def test_main_ctor_does_not_install_settings_hook(self):
        ctor = MAIN.split("%ctor {", 1)[1]
        self.assertNotIn("FBTInitGateSettingsAugment", ctor)
        self.assertIn("dispatch_async_f(dispatch_get_main_queue(), NULL, FBTBootstrapMainQueue)", ctor)


if __name__ == "__main__":
    unittest.main()
