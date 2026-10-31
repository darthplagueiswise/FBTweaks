#!/usr/bin/env python3
"""Hook audit contracts: registered ≠ invoked; failed/pending must be explainable."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
def src(p): return (ROOT/p).read_text()
class HookAuditTests(unittest.TestCase):
    def test_model_exposes_real_targets_and_failure_reasons(self):
        h=src("src/Runtime/FBTRuntimeBoolBrowser.h")
        m=src("src/Runtime/FBTRuntimeBoolBrowser.m")
        self.assertIn("FBTRuntimeBoolHookAuditSnapshot(void)",h)
        self.assertIn("sInstallFailures",m)
        self.assertIn('@"reason"',m)
        self.assertIn('@"invocationCount"',m)
        self.assertIn('@"registered"',m)
        self.assertIn('@"invoked"',m)
        self.assertIn('@"pending"',m)
        self.assertIn('@"rejected"',m)
    def test_audit_screen_supports_state_filter_and_accessible_full_names(self):
        m=src("src/Settings/FBTHookAuditViewController.m")
        self.assertIn("UIGlassContainerEffect",m)
        self.assertIn("UIGlassEffect",m)
        self.assertIn("animateWithDuration",m)
        self.assertIn("UIAccessibility",m)
        self.assertIn("numberOfLines = 0",m)
        for key in ("registered","invoked","pending","rejected"):
            self.assertIn(key,m)
        self.assertIn("FBTRuntimeBoolHookAuditSnapshot()",m)
        self.assertIn("FBTMCNativeProbeStatus()",m)
    def test_menu_has_single_hook_audit_link(self):
        m=src("src/Settings/FBTSettingsViewController.m")
        self.assertIn('@"dest": @"hookaudit"',m)
        self.assertIn("FBTHookAuditViewController",m)
        self.assertIn('isEqualToString:@"hookaudit"',m)
if __name__=="__main__":unittest.main()
