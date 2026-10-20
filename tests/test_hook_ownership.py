#!/usr/bin/env python3
"""Guard one hook owner per Objective-C selector and verify method ownership."""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(name):return (ROOT/name).read_text(encoding="utf-8")
class HookOwnership(unittest.TestCase):
 def test_runtime_browser_rejects_selectors_owned_by_symbol_browser(self):
  s=read("src/Runtime/FBTRuntimeBoolBrowser.m")
  self.assertIn("hookInstalledForKey:key",s)
 def test_symbol_browser_rejects_runtime_browser_ownership(self):
  s=read("src/Runtime/FBTSymbolBrowserEngine.m")
  self.assertIn("FBTRuntimeBoolHookInstalledForKey(key)",s)
 def test_runtime_browser_rejects_inherited_getters(self):
  s=read("src/Runtime/FBTRuntimeBoolBrowser.m")
  self.assertIn("class_copyMethodList(hookClass",s)
 def test_two_known_employee_getters_remain_single_owner(self):
  s=read("src/Runtime/FBTRuntimeBoolBrowser.m")
  self.assertIn('@"FBUserPreferences"',s)
  self.assertIn('@"FBUser"',s)
  self.assertIn('@"isEmployee"',s)
if __name__=="__main__": unittest.main()
