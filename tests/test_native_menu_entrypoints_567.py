"""Verified Facebook 567 native internal-menu navigation contract.

Source checks only: device-side initialization may still fail gracefully when
a native provider or coordinator has not been registered.
"""
import unittest
from pathlib import Path

R = Path(__file__).resolve().parents[1]
MENU = (R / "src/Runtime/FBTNativeInternalMenus.m").read_text(encoding="utf8")
UI = (R / "src/Settings/FBTSettingsViewController.m").read_text(encoding="utf8")
ROOT = (R / "src/Features/Dogfood/FBTDogfood.m").read_text(encoding="utf8")


class NativeMenuRoutes567(unittest.TestCase):
    def test_direct_controllers_have_distinct_native_implementations(self):
        for menu, cls in {
            "ffdb": "FFDBInternalSettingsViewController",
            "about": "FBAboutInternalSettingsViewController",
            "react_ota": "FBInternalSettingsReactOTAViewController",
            "on_demand": "FBInternalSettingsDownloadOnDemandViewController",
            "loggedout_push": "FBLoggedOutPushInternalSettingsViewController",
            "reliable_media": "FBReliableMediaInternalSettingsViewController",
            "clash": "FBClashManagementInternalSettingsTableViewController",
            "lifecycle": "FBLifecycleInternalSettingsViewController",
            "autofill_tokenization": "_TtC42AutofillTokenizationInternalSettingsPlugin52FBAutofillTokenizationInternalSettingsViewController",
            "messaging_thread": "_TtC43FBMessagingThreadViewInternalSettingsPlugin51FBMessagingThreadViewInternalSettingsViewController",
        }.items():
            self.assertIn(f'@"{menu}": @[@"{cls}"', MENU)
        self.assertIn('FBTNativeOpenController(menuID, &reason)', UI)
        self.assertIn('FBTNativeRequireClass(entry[0], &cls, failure)', MENU)
        self.assertIn('FBTNativeCheckInitializer', MENU)

    def test_context_dependent_menus_do_not_use_generic_search(self):
        self.assertIn('FBTNativeOpenEmployeeUserOption(&reason)', UI)
        self.assertIn('FBTNativeOpenDogfoodingAssistant(&reason)', UI)
        self.assertIn('@"nativePlugin": @"MobileConfig"', UI)
        self.assertNotIn('@"pluginSearch"', UI)
        self.assertNotIn('searchBar.text = targetSearch', ROOT)
        self.assertIn('FBTSelectNativeInternalPlugin', ROOT)
        self.assertIn('[table.delegate tableView:table didSelectRowAtIndexPath:found]', ROOT)

    def test_no_fake_native_dependencies(self):
        self.assertIn('if (!session || !navigationCoordinator || !tabID)', MENU)
        self.assertIn('FBBugReportInitialCoordinator', MENU)
        self.assertIn('openBugReportForm', MENU)
        self.assertNotIn('[[FBBugReportInitialCoordinator alloc]', MENU)
        self.assertNotIn('FBMobileConfigContextManagers managers = {nil', MENU)

    def test_no_new_dyld_constructors(self):
        self.assertNotIn('%ctor', MENU)
        self.assertNotIn('__attribute__((constructor))', MENU)
        self.assertNotIn('MSHookMessageEx', MENU)


if __name__ == "__main__":
    unittest.main()
