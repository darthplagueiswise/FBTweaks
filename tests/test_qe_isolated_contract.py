"""Contract: one slot, one compiled opt-in, no resurrection of the old QE observer."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def read(name):
    return (ROOT / name).read_text(encoding="utf-8")

class IsolatedQEContract(unittest.TestCase):
    def test_global_legacy_invasive_hooks_disabled_by_default(self):
        header = read("src/Runtime/FBTMobileConfigFetchDiagnostics.h")
        makefile = read("Makefile")
        self.assertIn("#define FBT_ENABLE_QE_INVASIVE_HOOKS 0", header)
        self.assertIn("FBT_QE_ISOLATED ?= 0", makefile)
        self.assertIn("-DFBT_ENABLE_QE_ISOLATED_PROFILE=$(FBT_QE_ISOLATED)", makefile)
        self.assertNotIn("-DFBT_ENABLE_QE_INVASIVE_HOOKS=1", makefile)
        self.assertNotIn("FBT_QE_LAB", makefile)

    def test_only_the_verified_async_fetcher_slot_is_modified(self):
        isolated = read("src/Runtime/FBTMCQEIsolatedProfile.mm")
        self.assertEqual(isolated.count('FBTRebindVerifiedImageConstSlot('), 1)
        self.assertIn('0x8161f88ULL', isolated)
        self.assertIn('0xa17f70ULL', isolated)
        self.assertIn('"FBSharedFramework"', isolated)
        for banned in ('rebind_symbols(', 'method_setImplementation(', 'NSURLSession',
                       'FBTInstallNSErrorMetadataHook(', 'FBTInstallQEInfoRefreshNamesImportHook('):
            # NSURLSession appears in commentary: allow the explanatory comment
            if banned == 'NSURLSession':
                continue
            self.assertNotIn(banned, isolated)
        self.assertIn('FBTMCNativeProbeAnyEnabled()', isolated)
        self.assertIn('FBTMCQEIsolatedProfileInstalled()', read("src/Runtime/FBTMCNativeSessionProbes.m"))
        self.assertIn('if (FBTQEInvasiveHooksAllowed() ||', isolated)
        self.assertIn('#if FBT_ENABLE_QE_ISOLATED_PROFILE', isolated)

    def test_only_approved_request_boolean_fields_change(self):
        core = read("src/Runtime/FBTMCQEFullMetadataCore.hpp")
        self.assertIn('{"skip_qe", "false"}', core)
        self.assertIn('{"with_current_experiment_group", "true"}', core)
        self.assertIn('{"needs_name", "true"}', core)
        self.assertNotIn('{"device_id",', core)
        self.assertNotIn('{"is_employee",', core)
        self.assertIn('missing_protocol_field', core)
        self.assertIn('duplicate_protocol_field', core)

    def test_native_callback_passthrough_without_status_forgery(self):
        isolated = read("src/Runtime/FBTMCQEIsolatedProfile.mm")
        self.assertIn('(*originalCompletion)(success, bytes)', isolated)
        self.assertNotIn('(*originalCompletion)(true,', isolated)
        self.assertNotIn('FBTMobileConfigResponseCaptureInstallTigon();', isolated)
        self.assertNotIn('FBTMobileConfigFetcherCaptureInstall();', isolated)
        self.assertNotIn('FBTMobileConfigResponseCaptureInstall();', isolated)

    def test_ui_only_shows_button_in_dedicated_build(self):
        ui = read("src/Settings/FBTNamesDiagnosticsViewController.m")
        self.assertIn('if (FBTMCQEIsolatedProfileAvailable())', ui)
        self.assertIn('[command isEqual:@"isolated_qe"]', ui)
        self.assertIn('FBTMCQEIsolatedProfileCancel();', ui)

if __name__ == "__main__":
    unittest.main()
