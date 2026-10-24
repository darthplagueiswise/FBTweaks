#!/usr/bin/env python3
"""Containment contract for the QE-info diagnostic crash surface.

Safe QE logging must not install C++ fishhooks, C++ vtable/data-const
trampolines, global NSURLSession hooks, or global NSError interception.
"""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(path):return (ROOT/path).read_text(encoding="utf-8")
class QEContainmentTests(unittest.TestCase):
    def test_invasive_backend_off_by_default(self):
        h=read("src/Runtime/FBTMobileConfigFetchDiagnostics.h")
        self.assertIn("#define FBT_ENABLE_QE_INVASIVE_HOOKS 0",h)
        self.assertIn("FBTQEInvasiveHooksAllowed",h)
    def test_all_deep_installers_guarded(self):
        mapping={
            "src/Runtime/FBTMobileConfigTigonCapture.mm":
                "void FBTMobileConfigResponseCaptureInstallTigon(void) {",
            "src/Runtime/FBTMobileConfigFetcherCapture.mm":
                "void FBTMobileConfigFetcherCaptureInstall(void) {",
            "src/Runtime/FBTMobileConfigResponseCapture.m":
                "void FBTMobileConfigResponseCaptureInstall(void) {",
            "src/Runtime/FBTMobileConfigDebugUIHooks.mm":
                "static void FBTInstallQEInfoFetchImportHook(void) {",
        }
        for path,entry in mapping.items():
            src=read(path)
            segment=src[src.index(entry):src.index(entry)+650]
            self.assertIn("FBTQEInvasiveHooksAllowed()",segment,path)
    def test_refresh_names_and_nserror_hooks_guarded(self):
        src=read("src/Runtime/FBTMobileConfigDebugUIHooks.mm")
        for name in ["static void FBTInstallNSErrorMetadataHook(void) {",
                     "static void FBTInstallQEInfoRefreshNamesImportHook(void) {",
                     "static void FBTInstallNamesAlertReporting(void) {"]:
            start=src.index(name)
            self.assertIn("FBTQEInvasiveHooksAllowed()",src[start:start+460],name)
    def test_safe_diagnostics_remains_useful(self):
        src=read("src/Runtime/FBTMobileConfigDebugUIHooks.mm")
        for event in ('@"item_selection_started"','@"qe_info_failure_alert"',
                      '@"selection_started"'):
            self.assertIn(event,src)
        ui=read("src/Settings/FBTSettingsViewController.m")
        self.assertIn("FBTKeyMobileConfigFetchDiagnosticsEnabled",ui)
        self.assertIn("FBTKeyMobileConfigFetchDiagnosticsEnabled",read("src/Settings/FBTSettingsCatalog.m"))
    def test_no_unverified_hooks_in_regular_ci(self):
        ci=read(".github/workflows/buildtweak.yml")
        self.assertIn('test_qe_safe_diagnostics.py',ci)
        self.assertIn("FBT_ENABLE_QE_INVASIVE_HOOKS",ci)
if __name__=="__main__":unittest.main()
