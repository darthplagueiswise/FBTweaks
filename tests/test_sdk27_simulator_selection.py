"""iOS 27 simulator selection: reject device-specific runtime ties and stale iPhone preference."""
import argparse
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scripts/test-uikit-simulator.py"
SPEC = importlib.util.spec_from_file_location("fbt_uikit_simulator", PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

RUNTIMES = [
    {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "version": "27.0", "isAvailable": True},
    {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4",
     "version": "27.2", "isAvailable": True},
    {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2", "version": "27.2", "isAvailable": True},
]
DEVICES = [
    {"name": "iPhone 18 Pro Max", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max",
     "minRuntimeVersionString": "27.0", "maxRuntimeVersionString": "65535.255.255"},
    {"name": "iPhone 11", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-11",
     "minRuntimeVersionString": "13.0", "maxRuntimeVersionString": "65535.255.255"},
]

class SimulatorSelectionTests(unittest.TestCase):
    def make_runner(self, runtime=None, device_type=None):
        runner = object.__new__(MODULE.Runner)
        runner.args = argparse.Namespace(runtime=runtime, device_type=device_type)
        def fixture(argv):
            if "runtimes" in argv:
                return {"runtimes": RUNTIMES}
            if "devicetypes" in argv:
                return {"devicetypes": DEVICES}
            raise AssertionError(f"Unexpected simulated CLI call: {argv}")
        runner.json_command = fixture
        return runner

    def test_generic_runtime_beats_device_specific_variant_at_same_version(self):
        runtime, device = self.make_runner().select_simulator()
        self.assertEqual(runtime["identifier"], "com.apple.CoreSimulator.SimRuntime.iOS-27-2")
        self.assertEqual(device["name"], "iPhone 18 Pro Max")

    def test_explicit_runtime_is_honored(self):
        wanted = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
        runtime, _ = self.make_runner(runtime=wanted).select_simulator()
        self.assertEqual(runtime["identifier"], wanted)

if __name__ == "__main__":
    unittest.main()
