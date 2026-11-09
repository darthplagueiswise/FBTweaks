"""Regression checks for UIKit Liquid Glass submenus and genuine native actions.

These are source contract checks. On-device tests are still required for
React bridges, private native session providers and the Gold callback.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI = (ROOT / "src/Settings/FBTSettingsViewController.m").read_text(encoding="utf-8")
DOGFOOD = (ROOT / "src/Runtime/FBTDogFoodNative.m").read_text(encoding="utf-8")
NATIVE = (ROOT / "src/Features/Dogfood/FBTDogfood.m").read_text(encoding="utf-8")


class SettingsNavigationContracts(unittest.TestCase):
    def test_root_is_compact_and_all_submenus_have_click_routes(self):
        for group in ("employee", "native_controllers", "dogfood", "react",
                      "mobileconfig", "diagnostics", "appearance"):
            self.assertIn(f'@"group": @"{group}"', UI)
            self.assertIn(f'[self.menuGroup isEqualToString:@"{group}"]', UI)
        self.assertIn('[kind isEqualToString:@"submenu"]', UI)
        self.assertIn('pushViewController:controller animated:YES', UI)
        self.assertIn('self.sectionTitles', UI)

    def test_system_liquid_glass_not_overridden_with_opaque_nav_bar(self):
        self.assertIn('UIGlassEffect', UI)
        self.assertIn('UIVisualEffectView', UI)
        self.assertIn('@available(iOS 26.0, *)', UI)
        self.assertNotIn('bar.standardAppearance = nil', UI)
        self.assertIn('UINavigationItemLargeTitleDisplayModeAlways', UI)

    def test_dogfood_flag_is_separate_and_editable_from_its_submenu(self):
        self.assertIn('@"FBDogFood-managedPhoneFlag"', UI)
        self.assertIn('FBTDogFoodSetManagedPhoneFlag(sender.isOn)', UI)
        self.assertIn('FBTDogFoodManagedPhoneFlag()', UI)
        self.assertIn('FBTDogFoodSetManagedPhoneFlag(YES)', DOGFOOD)
        self.assertNotIn('FBTKeyEmployeeEnabled', DOGFOOD)

    def test_known_natives_do_not_get_fabricated_plugins(self):
        for action in ("native", "rn_internal", "rn_dev", "dogfood_nag", "whitehat"):
            self.assertIn(f'[action isEqualToString:@"{action}"]', UI)
        for target in ("dogfood_assistant", "ffdb_internal", "mc_debug_native",
                       "employee_internal"):
            self.assertIn(f'[action isEqualToString:@"{target}"]', UI)
        native_menus = (ROOT / "src/Runtime/FBTNativeInternalMenus.m").read_text(encoding="utf-8")
        self.assertNotIn('@"pluginSearch"', UI)
        self.assertNotIn('UISearchController *search = vc.navigationItem.searchController', NATIVE)
        self.assertIn('FBTNativeOpenController(menuID, &reason)', UI)
        self.assertIn('FBTNativeOpenDogfoodingAssistant(&reason)', UI)
        self.assertIn('FBTNativeOpenEmployeeUserOption(&reason)', UI)
        self.assertIn('@"nativePlugin": @"MobileConfig"', UI)
        self.assertIn('FBTSelectNativeInternalPlugin', NATIVE)
        self.assertIn('tableView:didSelectRowAtIndexPath:', NATIVE)
        self.assertIn('FFDBInternalSettingsViewController', native_menus)
        self.assertNotIn('[FFDBInternalSettingsViewController alloc]', UI)


if __name__ == "__main__":
    unittest.main()
