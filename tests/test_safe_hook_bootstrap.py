#!/usr/bin/env python3
"""Regression guard: arbitrary selector hooks must not run during dyld initializers."""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(path):return (ROOT/path).read_text(encoding="utf-8")
class SafeHookBootstrap(unittest.TestCase):
    def test_no_dynamic_selector_restoration_in_constructor(self):
        src=read("src/Tweak.x")
        ctor=src[src.index("%ctor {"):]
        self.assertNotIn("FBTRuntimeBoolReinstallPersistedHooks();",ctor)
        self.assertNotIn("[FBTSymbolBrowserEngine reinstallPersistedHooks];",ctor)
    def test_restore_deferred_until_ui_is_alive(self):
        src=read("src/Tweak.x")
        self.assertIn("dispatch_after(",src)
        self.assertIn("FBTRuntimeBoolReinstallPersistedHooks();",src)
        self.assertIn("[FBTSymbolBrowserEngine reinstallPersistedHooks];",src)
    def test_passive_observers_are_not_automatically_reinstalled(self):
        src=read("src/Runtime/FBTRuntimeBoolBrowser.m")
        start=src.index("void FBTRuntimeBoolReinstallPersistedHooks(void)")
        end=src.index("void FBTRuntimeBoolRetryPendingHooks",start)
        section=src[start:end]
        self.assertIn('@"observe"',section)
        self.assertIn("continue;",section)
    def test_readonly_user_action_remains_available(self):
        src=read("src/Runtime/FBTRuntimeBoolBrowser.m")
        self.assertIn("void FBTRuntimeBoolObserve(",src)
        self.assertIn('@"source": @"observe"',src)
if __name__=="__main__":unittest.main()
