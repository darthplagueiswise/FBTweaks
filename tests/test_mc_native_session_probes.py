#!/usr/bin/env python3
"""Session-only, fail-closed verification of the experimental native callback probes."""
import unittest
from pathlib import Path
R = Path(__file__).resolve().parents[1]
def src(p): return (R / p).read_text(encoding="utf-8")
class MCNativeSessionProbes(unittest.TestCase):
    def test_session_only_and_real_toggles(self):
        state = src("src/Runtime/FBTMCNativeSessionProbes.m")
        ui = src("src/Settings/FBTSettingsViewController.m")
        self.assertIn("atomic_bool",state)
        self.assertIn("FBTMCNativeProbeSetEnabled(sender.prefKey, sender.isOn",ui)
        self.assertIn("FBTMCNativeProbeTigonKey",src("src/Settings/FBTSettingsCatalog.m"))
        self.assertIn("FBTMCNativeProbeFetcherKey",src("src/Settings/FBTSettingsCatalog.m"))
        self.assertNotIn("setBool:",state)
        self.assertNotIn("standardUserDefaults",state)
        self.assertIn("if (!installed) atomic_store_explicit",state)
    def test_cpp_linkage_for_objective_c_native_session_probes(self):
        header = src("src/Runtime/FBTMCNativeSessionProbes.h")
        self.assertIn('extern "C" {', header)
        self.assertIn('#ifdef __cplusplus\n}\n#endif', header)
        smoke = src("tests/MCNativeProbeLinkTests.mm")
        self.assertIn('FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey)', smoke)
        workflow = src(".github/workflows/buildtweak.yml")
        self.assertIn('tests/MCNativeProbeLinkTests.mm', workflow)
    def test_qe_diagnostics_off_disarms_both_probe_switches(self):
        state = src("src/Runtime/FBTMCNativeSessionProbes.m")
        ui = src("src/Settings/FBTSettingsViewController.m")
        self.assertIn("void FBTMCNativeProbeDisableAll(void)", state)
        self.assertIn("atomic_store_explicit(&sTigonEnabled, false", state)
        self.assertIn("atomic_store_explicit(&sFetcherEnabled, false", state)
        self.assertIn("FBTMCNativeProbeDisableAll();", ui)
        self.assertIn("[self.tableView reloadData]; // Session-only native probes", ui)
    def test_uuid_slot_binding_not_text_patching(self):
        tig = src("src/Runtime/FBTMobileConfigTigonCapture.mm")
        fetch = src("src/Runtime/FBTMobileConfigFetcherCapture.mm")
        for text in (tig,fetch):
            self.assertIn("FBTRebindVerifiedImageConstSlot",text)
            self.assertNotIn("Interceptor.attach",text)
        self.assertIn("if (!FBTQEInvasiveHooksAllowed()) return;",tig)
        self.assertIn("FBTMCNativeProbeIsEnabled(FBTMCNativeProbeTigonKey)",tig)
        self.assertIn("FBTMCNativeProbeIsEnabled(FBTMCNativeProbeFetcherKey)",fetch)
    def test_opt_in_observation_does_not_mutate_server_requests_or_store_bodies(self):
        fetch = src("src/Runtime/FBTMobileConfigFetcherCapture.mm")
        tig = src("src/Runtime/FBTMobileConfigTigonCapture.mm")
        self.assertIn("if (!FBTQEInvasiveHooksAllowed()) sRequestExperiment.cancel();",fetch)
        self.assertIn("if (FBTQEInvasiveHooksAllowed() && success",fetch)
        self.assertIn("} else if (FBTQEInvasiveHooksAllowed()) {",tig)
        self.assertIn('@"tigon_native_response_metadata"',tig)
    def test_legacy_lab_fixture_has_explicit_separate_opt_in(self):
        fixture = src("tests/TigonCaptureTests.mm")
        self.assertIn("#define FBT_ENABLE_QE_INVASIVE_HOOKS 1", fixture)
        self.assertIn("BOOL FBTMCNativeProbeIsEnabled(NSString *key)", fixture)
        self.assertIn("FBTMCNativeProbeFetcherKey", fixture)
        self.assertIn("FBTMCNativeProbeTigonKey", fixture)
    def test_no_default_invasive_mode(self):
        hdr = src("src/Runtime/FBTMobileConfigFetchDiagnostics.h")
        self.assertIn("#define FBT_ENABLE_QE_INVASIVE_HOOKS 0",hdr)
        info = src("src/Runtime/FBTMobileConfigFetchDiagnostics.m")
        self.assertIn("native_opt_in_session_callbacks",info)
if __name__ == "__main__":
    unittest.main()
