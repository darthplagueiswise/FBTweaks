#!/usr/bin/env python3
"""Regression contracts for runtime BOOL browser: truthful installation and persistence."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
def read(p): return (R/p).read_text()
class RuntimeBoolIntegrity(unittest.TestCase):
    def test_sweeps_require_master_and_count_only_installed(self):
        s=read("src/Runtime/FBTRuntimeBoolBrowser.m")
        seg=s.split("NSUInteger FBTRuntimeBoolInstallSweep(",1)[1].split("NSDictionary *FBTRuntimeBoolSweepStats(",1)[0]
        self.assertIn("FBTKeyRuntimeBoolBrowserEnabled",seg)
        self.assertNotIn("sBoolBrowserEnabled = YES;",seg)
        self.assertIn("FBTRuntimeBoolInstallOne(",seg)
        self.assertIn("FBTRuntimeBoolHookInstalledForKey(key)",seg)
        self.assertIn("++rejected",seg)
        self.assertIn("++alreadyOwned",seg)

    def test_runtime_search_classifies_and_exposes_exact_names_and_abi(self):
        s=read("src/Runtime/FBTRuntimeBoolBrowser.m")
        self.assertIn('@"category": FBTBoolCategory(className, sel)',s)
        self.assertIn('@"signature":',s)
        self.assertNotIn("FBTBoolRelevance",s)
        ui=read("src/Settings/FBTSettingsViewController.m")
        self.assertIn('[e[@"class"]',ui)
        self.assertIn('[e[@"selector"]',ui)
        self.assertIn("cfg.textProperties.numberOfLines = 0;",ui)
        self.assertIn("self.tableView.rowHeight = UITableViewAutomaticDimension;",ui)

    def test_switch_off_removes_only_sweep_force(self):
        ui=read("src/Settings/FBTSettingsViewController.m")
        self.assertIn("FBTRuntimeBoolClearSweep(mode);",ui)
        self.assertIn("FBTKeyRuntimeBoolBrowserEnabled",ui)
        self.assertIn('@"skipped_other_owner"',read("src/Runtime/FBTRuntimeBoolBrowser.m"))

    def test_clear_sweep_keeps_manual(self):
        s=read("src/Runtime/FBTRuntimeBoolBrowser.m")
        clear=s.split("void FBTRuntimeBoolClearSweep(",1)[1].split("void FBTRuntimeBoolClearAllOverrides",1)[0]
        self.assertIn('[entry[@"source"] isEqualToString:source]',clear)
        self.assertIn("FBTRuntimeBoolReloadPrefs();",clear)
if __name__=="__main__":unittest.main()
