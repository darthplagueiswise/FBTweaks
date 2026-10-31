#!/usr/bin/env python3
"""A BOOL browser must enumerate type-verified entities, not names that 'look relevant'."""
from pathlib import Path
import unittest
R = Path(__file__).resolve().parents[1]
def source(p):return (R/p).read_text()
class BoolMetadataContracts(unittest.TestCase):
    def test_methods_are_type_verified_without_name_allowlist(self):
        s=source("src/Runtime/FBTRuntimeBoolBrowser.m")
        methods=s.split("static void FBTAppendMethodsForClass(",1)[1].split("NSArray<NSDictionary *> *FBTRuntimeBoolSearch(",1)[0]
        self.assertIn("method_getReturnType",methods)
        self.assertIn("ret[0] != 'B'",methods)
        self.assertNotIn("FBTSelectorLooksUseful",methods)
        self.assertNotIn("FBTClassLooksUseful",methods)
        self.assertNotIn("ret[0] == 'c'",methods)
        search=s.split("NSArray<NSDictionary *> *FBTRuntimeBoolSearch(",1)[1].split("static NSMutableDictionary *sSweepStats",1)[0]
        self.assertNotIn("FBTBoolRelevance",search)
        self.assertNotIn("scanLimit",search)
    def test_char_does_not_get_bool_hook(self):
        s=source("src/Runtime/FBTRuntimeBoolBrowser.m")
        installation=s.split("static BOOL FBTRuntimeBoolInstallOne(",1)[1].split("void FBTRuntimeBoolMigrateLegacySymbolOverrides",1)[0]
        self.assertIn("ret[0] != 'B'",installation)
        self.assertNotIn("c16@0:8",installation)
    def test_boolean_ivars_are_read_only_and_explicit(self):
        hdr=source("src/Runtime/FBTRuntimeBoolBrowser.h")
        s=source("src/Runtime/FBTRuntimeBoolBrowser.m")
        ui=source("src/Settings/FBTSettingsViewController.m")
        self.assertIn("FBTRuntimeBoolSearchIvars",hdr)
        self.assertIn("class_copyIvarList",s)
        self.assertIn("ivar_getTypeEncoding",s)
        self.assertIn("strcmp(encoding, \"B\")",s)
        self.assertIn('@"entityType": @"ivar"',s)
        self.assertIn("Sem hook: armazenamento de dados, não método",ui)
    def test_methods_unrestricted_scan_uses_query_only(self):
        s=source("src/Runtime/FBTRuntimeBoolBrowser.m")
        search=s.split("NSArray<NSDictionary *> *FBTRuntimeBoolSearch(",1)[1].split("static NSMutableDictionary *sSweepStats",1)[0]
        self.assertIn("objc_getClassList",search)
        self.assertIn("FBTAppendMethodsForClass",search)
        self.assertNotIn("FBTSelectorLooksUseful",search)
    def test_clear_method_honors_call_and_active_override_state(self):
        s=source("src/Runtime/FBTRuntimeBoolBrowser.m")
        self.assertIn('@"activeForce"',s)
        self.assertIn('@"invocationCount"',s)
if __name__=="__main__":unittest.main()
