#!/usr/bin/env python3
"""Read-only MobileConfig source integration contracts (no device hooks)."""
import unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
def src(p): return (R/p).read_text(encoding="utf-8")
class MCReadonlySourceContract(unittest.TestCase):
    def test_no_native_code_write_in_new_probe(self):
        s=src("src/Runtime/FBTMCReadonlyTrace.m")
        for forbidden in ["vm_protect", "method_setImplementation", "rebind_symbols", "Interceptor.attach"]:
            self.assertNotIn(forbidden,s)
        self.assertIn("LC_UUID",s)
    def test_sanitization_precedes_recorder(self):
        s=src("src/Runtime/FBTMobileConfigFetchDiagnostics.m")
        self.assertLess(s.index('FBTDiagSafeEvent(event, details'),s.index('FBTNativeTraceRecordNetwork(event, safeEvent)'))
        self.assertIn('mc_value_source_bucket',s)
    def test_source_read_is_observational_and_optional(self):
        s=src("src/Runtime/FBTMobileConfigValueReader.m")
        self.assertIn('FBTMCNativeValueSourceObserved',s)
        self.assertIn('postNotificationName:',s)
        self.assertNotIn('FBTMobileConfigFetchDiagnosticsRecord(',s)
        self.assertIn('@"SERVER"',s)
        self.assertIn('@"DEFAULT"',s)
        self.assertNotIn('setBool:YES forKey',s)
    def test_source_notification_bridge(self):
        s=src("src/Runtime/FBTMCReadonlyTrace.m")
        self.assertIn('addObserverForName:@"FBTMCNativeValueSourceObserved"',s)
        self.assertIn('mc_native_value_source_observed',s)
    def test_no_unsafe_override_to_build_defaults(self):
        s=src("src/Runtime/FBTMobileConfigFetchDiagnostics.h")
        self.assertIn('#define FBT_ENABLE_QE_INVASIVE_HOOKS 0',s)
if __name__=="__main__": unittest.main()
