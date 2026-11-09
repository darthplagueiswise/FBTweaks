"""Static contract checks for native Facebook 567 internal surfaces.

These tests complement (but do not replace) on-device UI/ABI validation.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "src/Settings/FBTSettingsViewController.m"
NATIVE = ROOT / "src/Runtime/FBTNativeInternalSurfaces.m"
GOLD = ROOT / "src/Runtime/FBTDogFoodNative.m"


class NativeInternalSurfacesContracts(unittest.TestCase):
    def test_all_declared_menu_actions_have_handlers(self):
        text = UI.read_text(encoding="utf-8")
        for action in (
            "rn_internal", "rn_dev", "dogfood_assistant", "ffdb_internal",
            "mc_debug_native", "employee_internal", "gold_status",
            "gold_builds", "native_surfaces_diag", "dogfood_nag"
        ):
            self.assertIn(f'@"action": @"{action}"', text)
            self.assertIn(f'[action isEqualToString:@"{action}"]', text)

    def test_rn_devmenu_uses_live_module_and_exact_method(self):
        text = NATIVE.read_text(encoding="utf-8")
        self.assertIn('moduleForClass:', text)
        self.assertIn('FBTNSFindLiveDevMenu', text)
        self.assertIn('SEL show = @selector(show)', text)
        self.assertIn('method_getNumberOfArguments(method) != 2', text)
        self.assertNotIn('[[RCTDevMenu alloc] init]', text)

    def test_gold_callbacks_do_not_force_obsolete_slots_or_modify_tokens(self):
        text = GOLD.read_text(encoding="utf-8")
        self.assertIn('getNagSheetWithSession:title:message:switchButtonText:', text)
        # Gold/managed-phone is intentionally independent of Employee.
        self.assertNotIn('FBTKeyEmployeeEnabled', text)
        self.assertIn('FBTDogFoodSetManagedPhoneFlag(YES)', text)
        self.assertIn('FBDogFood-managedPhoneFlag', text)
        self.assertNotIn('FBGRDogFoodApplyMCOverrides', text)
        self.assertNotIn('Authorization:', text)
        self.assertNotIn('access_token', text)

    def test_unverified_plugins_are_not_instantiated_without_native_providers(self):
        text = UI.read_text(encoding="utf-8")
        for name in (
            "FFDBInternalSettingsViewController",
            "FBMobileConfigDebugViewController",
            "FBClientRageShakeBugReporterViewController"
        ):
            # UI maps them to the native Internal Settings plugin root instead
            # of calling a guessed initWithSession: or plain init.
            self.assertNotIn(f'[{name} alloc]', text)
        self.assertIn('FBTRequestOpenNativeInternalSettings', text)


if __name__ == "__main__":
    unittest.main()
