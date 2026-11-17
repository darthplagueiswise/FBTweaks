"""Fail-closed source checks for the real Xcode 27 / Theos SDK 27.1 CI target."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

class SDK27BuildContracts(unittest.TestCase):
    def test_runner_and_sdk(self):
        workflow = read(".github/workflows/buildtweak.yml")
        self.assertIn("runs-on: xcode-27", workflow)
        self.assertIn("SDK_NAME: iPhoneOS27.1.sdk", workflow)
        self.assertIn("scripts/validate-sdk27.sh", workflow)
        self.assertIn("bash build.sh rootless", workflow)
        self.assertIn("scripts/verify_macho_installation.sh", workflow)
        self.assertIn("FBTweak-rootless-arm64-", workflow)
        self.assertIn("if-no-files-found: error", workflow)
        self.assertEqual(workflow.count("--runtime com.apple.CoreSimulator.SimRuntime.iOS-27-2 --command-timeout 300 --boot-timeout 300"), 2)
        self.assertEqual(workflow.count("--device-type com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max"), 2)
        self.assertLess(workflow.index("- name: Build and verify rootless package"), workflow.index("- name: Reproduce previous UIKit"))
        self.assertLess(workflow.index("- name: Test UIKit navigation"), workflow.index("- name: Upload verified rootless artifact"))

    def test_makefile(self):
        makefile = read("Makefile")
        self.assertIn("TARGET := iphone:clang:27.1:16.3", makefile)
        self.assertIn("iPhoneOS27.1.sdk/System/Library/SubFrameworks", makefile)
        self.assertIn("ARCHS = arm64", makefile)

    def test_validator(self):
        validator = read("scripts/validate-sdk27.sh")
        self.assertIn("iPhoneOS27.1.sdk", validator)
        self.assertIn("iphone:clang:27.1:16.3", validator)

    def test_uikit_simulator(self):
        runner = read("scripts/test-uikit-simulator.py")
        host = read("tests/UIKitRegressionHost.m")
        self.assertIn("apple-ios27.0-simulator", runner)
        self.assertIn('"runtime.ios27"', runner)
        self.assertIn('@"runtime.ios27"', host)
        self.assertIn("iOS 27.0", host)
        self.assertIn("search.native_activation", host)

if __name__ == "__main__":
    unittest.main()
