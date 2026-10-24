"""Fail-closed regression checks: PR #5 observational baseline must remain unchanged.

The no-injection proxy A/B comparer is deliberately not a new QE hook.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
def source(path):
    return (ROOT / path).read_text(encoding="utf-8")

class QEObservationalOnlyRegression(unittest.TestCase):
    def test_global_invasive_switch_stays_off(self):
        makefile = source('Makefile')
        header = source('src/Runtime/FBTMobileConfigFetchDiagnostics.h')
        workflow = source('.github/workflows/buildtweak.yml')
        self.assertIn('#define FBT_ENABLE_QE_INVASIVE_HOOKS 0', header)
        self.assertNotIn('FBT_QE_LAB', makefile)
        self.assertNotIn('FBT_QE_LAB', workflow)
        self.assertNotIn('-DFBT_ENABLE_QE_INVASIVE_HOOKS=1', makefile)
        self.assertNotIn('QE-LAB artifact', workflow)

    def test_native_abi_hooks_are_not_extended(self):
        fetcher = source('src/Runtime/FBTMobileConfigFetcherCapture.mm')
        experiments = source('src/Runtime/FBTMCRequestExperiment.hpp')
        ui = source('src/Settings/FBTNamesDiagnosticsViewController.m')
        for text in (fetcher, experiments, ui):
            self.assertNotIn('FullMetadataExperiment', text)
            self.assertNotIn('applyFullMetadata', text)
            self.assertNotIn('C_qe_full_metadata', text)
        self.assertIn('if (!FBTQEInvasiveHooksAllowed()) sRequestExperiment.cancel();', fetcher)
        self.assertIn('FBTQEInvasiveHooksAllowed()', fetcher)

    def test_proxy_can_only_observe(self):
        addon = source('scripts/qe_proxy/addon.py')
        compare = source('scripts/qe_proxy/compare_profiles.py')
        self.assertIn('summarize_request', addon)
        self.assertIn('summarize_response', addon)
        self.assertNotIn('flow.request.content =', addon)
        self.assertNotIn('flow.response.content =', addon)
        self.assertNotIn('flow.request.headers[', addon)
        self.assertIn('server_eligibility_granted', compare)
        self.assertIn('not_inferable_from_client_flags', compare)

if __name__ == '__main__':
    unittest.main()
