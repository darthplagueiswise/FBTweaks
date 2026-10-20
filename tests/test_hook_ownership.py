#!/usr/bin/env python3
"""One Objective-C hook owner shared by both browsers."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
def read(p):return (R/p).read_text(encoding="utf-8")
class HookOwnership(unittest.TestCase):
 def test_only_one_dynamic_bool_installer(self):
  symbol=read("src/Runtime/FBTSymbolBrowserEngine.m")
  core=read("src/Runtime/FBTRuntimeBoolBrowser.m")
  self.assertNotIn("MSHookMessageEx(",symbol)
  self.assertIn("MSHookMessageEx(hookClass",core)
  self.assertIn("FBTRuntimeBoolInstallPersistedKey(key)",symbol)
 def test_previous_symbol_preferences_migrate_preserving_existing(self):
  core=read("src/Runtime/FBTRuntimeBoolBrowser.m")
  self.assertIn('@"fbt_symbol_overrides_migrated_v1"',core)
  self.assertIn("|| merged[key]) continue;",core)
  self.assertIn('@"symbol-legacy"',core)
 def test_unknown_native_values_not_invoked_from_list(self):
  browser=read("src/Runtime/FBTSymbolBrowserEngine.m")
  self.assertNotIn("objc_msgSend",browser)
  self.assertIn("FBTRuntimeBoolObservedOriginal",browser)
 def test_exact_abi_and_known_employee_selector_ownership(self):
  core=read("src/Runtime/FBTRuntimeBoolBrowser.m")
  for value in ('strcmp(encoding,"B16@0:8")','strcmp(encoding,"c16@0:8")','class_copyMethodList(hookClass','@"FBUserPreferences"','@"FBUser"'):
   self.assertIn(value,core)
if __name__=="__main__":unittest.main()
