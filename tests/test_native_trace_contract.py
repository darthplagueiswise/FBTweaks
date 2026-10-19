#!/usr/bin/env python3
"""Static integration checks; device behavior requires IPA validation."""
import unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
def src(path): return (R/path).read_text(encoding="utf-8")
class NativeTraceContract(unittest.TestCase):
    def test_trace_is_opt_in(self):
        d=src("src/FBTDefaults.m")
        self.assertIn('FBTKeyNativeTraceEnabled:               @(NO)', d)
    def test_live_trace_is_reachable(self):
        s=src("src/Settings/FBTSettingsViewController.m")
        self.assertIn('@"dest": @"livetrace"',s)
        self.assertIn('@"dest": @"boollive"',s)
        self.assertIn('FBTRuntimeBoolObserve(e)',s)
    def test_passive_observation_is_persisted(self):
        s=src("src/Runtime/FBTRuntimeBoolBrowser.m")
        b=s.index("void FBTRuntimeBoolObserve(")
        e=s.index("void FBTRuntimeBoolClearOverride(",b)
        body=s[b:e]
        self.assertIn('@"source": @"observe"',body)
        self.assertNotIn('@"force":',body)
        self.assertLess(body.index("[FBTDefaults setDict:all"),body.index("FBTRuntimeBoolInstallOne("))
    def test_hook_sampling_does_not_call_original_twice(self):
        s=src("src/Runtime/FBTRuntimeBoolBrowser.m")
        h=s[s.index("IMP replacement = imp_implementationWithBlock"):s.index("MSHookMessageEx(hookClass")]
        self.assertIn('count % 128 == 0',h)
        self.assertEqual(h.count('captured->orig ?'),1)
        self.assertIn('FBTNativeTraceRecordBool',h)
    def test_mobileconfig_safe_bridge(self):
        s=src("src/Runtime/FBTMobileConfigFetchDiagnostics.m")
        self.assertLess(s.index("FBTDiagSafeEvent(event, details"),s.index("FBTNativeTraceRecordNetwork(event, safeEvent)"))
        self.assertIn("if (!fullLogEnabled) return;",s)
    def test_no_frida_dependency(self):
        for p in ["src/Runtime/FBTNativeTrace.mm","src/Runtime/FBTNativeTraceCore.hpp","src/Settings/FBTNativeTraceViewController.m"]:
            self.assertNotIn("FridaGadget",src(p))
            self.assertNotIn("Interceptor.attach",src(p))
if __name__=="__main__":unittest.main()
