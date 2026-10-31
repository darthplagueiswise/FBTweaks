#!/usr/bin/env python3
"""Source contracts: one central diagnostic flow, real switches, visible armed state.

These tests intentionally fail on the previous text-only list implementation.
"""
import unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
def read(path): return (R/path).read_text(encoding="utf-8")
class UnifiedDiagnosticsDesignTests(unittest.TestCase):
    def test_main_menu_has_single_central_entry_and_role_based_sections(self):
        s=read("src/Settings/FBTSettingsViewController.m")
        part=s.split("- (void)rebuildSections {",1)[1].split("- (NSString *)tableView:",1)[0]
        self.assertEqual(part.count('@"dest": @"namesdiagnostic"'), 1)
        self.assertIn('@"Centro de Diagnósticos"', part)
        for name in ('@"Essencial"', '@"Employee e laboratório"', '@"MobileConfig"', '@"Aparência e recursos"',
                     '@"Instrumentação avançada"', '@"Biblioteca de ferramentas"', '@"Manutenção"'):
            self.assertIn(name, s)
        self.assertNotIn('@"key": FBTMCNativeProbeFetcherKey',part)
        self.assertNotIn('@"key": FBTMCNativeProbeTigonKey',part)

    def test_controls_have_real_accessible_switches_and_buttons(self):
        s=read("src/Settings/FBTNamesDiagnosticsViewController.m")
        for name in ("UISegmentedControl","UISwitch","UIButtonConfiguration",
                     "prominentGlassButtonConfiguration","glassButtonConfiguration",
                     "accessibilityIdentifier", "FBTMCNativeProbeSetEnabled"):
            self.assertIn(name,s)
        self.assertIn("fbt.diagnostics.arm",s)
        self.assertIn("fbt.diagnostics.cancel",s)
        self.assertIn("fbt.diagnostics.fetcher",s)
        self.assertIn("fbt.diagnostics.tigon",s)

    def test_probe_gate_blocks_fake_arm_and_enables_only_on_success(self):
        s=read("src/Settings/FBTNamesDiagnosticsViewController.m")
        self.assertIn("FBTMCNativeProbeIsEnabled(FBTMCNativeProbeFetcherKey)", s)
        self.assertIn("FBTMobileConfigFetcherCaptureStatus()", s)
        self.assertIn("FBTMobileConfigArmEmployeeExperiment(", s)
        self.assertIn("FBTMobileConfigCancelEmployeeExperiment()", s)
        self.assertIn("@" + '"Probe indisponível"' ,s)

    def test_remaining_time_and_request_consumption_are_reported(self):
        s=read("src/Runtime/FBTMobileConfigFetcherCapture.mm")
        self.assertIn('@"expires_in_seconds"',s)
        self.assertIn('@"full_qe_profile"',s)
        ui=read("src/Settings/FBTNamesDiagnosticsViewController.m")
        self.assertIn('@"experiment_profile"',ui)
        self.assertIn('@"employee_field_added"',ui)
        self.assertIn("secondsRemaining",ui)

    def test_diagnostics_nav_is_not_forced_to_legacy_opaque_navbar(self):
        s=read("src/Settings/FBTSettingsViewController.m")
        self.assertIn("@available(iOS 26.0, *)",s)
        self.assertIn("prefersLargeTitles",s)
        self.assertNotIn("configureWithDefaultBackground",s)

if __name__=="__main__": unittest.main()
