"""Regression contracts for watchdog-safe MobileConfig read instrumentation.

These source-level tests run on Linux/macOS; runtime watchdog validation still
requires a device with the matching Mach-O UUID.
"""
from pathlib import Path
import re
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "src/Runtime/FBTMobileConfigRuntime.m").read_text()


def function_body(name):
    pattern = r"\b(?:static\s+)?void\s+" + re.escape(name) + r"\s*\("
    found = re.search(pattern, SOURCE)
    if not found:
        raise AssertionError(f"Missing {name}")
    start = SOURCE.index("{", found.end())
    level = 1
    for i in range(start + 1, len(SOURCE)):
        level += (SOURCE[i] == "{") - (SOURCE[i] == "}")
        if level == 0:
            return SOURCE[start + 1 : i]
    raise AssertionError(f"Unterminated {name}")


class WatchdogMobileConfigTests(unittest.TestCase):
    def test_reader_guard_precedes_object_formatting(self):
        body = function_body("FBTMobileConfigRecordAccess")
        self.assertLess(body.index("FBTMCShouldRecord(overridden)"), body.index("FBTMCObjectDescription(defaultValue)"))
        self.assertLess(body.index("sRecordDepth"), body.index("FBTMCObjectDescription(defaultValue)"))

    def test_reentrancy_state_is_reset_even_on_exception(self):
        for name in ("FBTMCRecord", "FBTMobileConfigRecordAccess"):
            body = function_body(name)
            self.assertIn("++sRecordDepth", body)
            self.assertIn("@finally", body)
            self.assertIn("--sRecordDepth", body)

    def test_background_shutdown_disables_optional_recording(self):
        self.assertIn("UIApplicationWillResignActiveNotification", SOURCE)
        self.assertIn("UIApplicationDidEnterBackgroundNotification", SOURCE)
        self.assertIn("UIApplicationDidBecomeActiveNotification", SOURCE)
        self.assertIn("atomic_load_explicit(&sAppQuiescing", SOURCE)

    def test_numeric_and_string_getters_skip_disabled_capture_formatting(self):
        for kind in ("int64", "double", "string"):
            self.assertRegex(SOURCE, r"if \(FBTMCShouldRecord\(NO\)\) FBTMCRecord\(key, @\"" + kind + r"\"")
            self.assertRegex(SOURCE, r"if \(FBTMCShouldRecord\(YES\)\) FBTMCRecord\(key, @\"" + kind + r"\"")


if __name__ == "__main__":
    unittest.main()
