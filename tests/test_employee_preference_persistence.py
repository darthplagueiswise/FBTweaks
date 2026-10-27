"""Run the production Logos preference method bodies against a native preference store.

Only %orig is adapted to the fixture's backing methods. This exercises the
getter/setter logic, not Substrate installation or the device's private classes.
"""
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EmployeePreferencePersistence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="fbt-employee-prefs-")
        cls.addClassCleanup(cls.tmp.cleanup)
        source = (ROOT / "src/Features/Employee/FBTEmployeeMode.x").read_text()
        methods = source.split("%hook FBUserPreferences\n", 1)[1].split("%end", 1)[0]
        methods = methods.replace("%orig(effective)", "[self originalSetEmployee:effective]")
        methods = methods.replace("%orig", "[self originalIsEmployee]")
        fixture = (ROOT / "tests/EmployeePreferencePersistenceFixture.m").read_text()
        path = Path(cls.tmp.name) / "fixture.m"
        path.write_text(fixture.replace("/* PRODUCTION_PREFERENCE_METHODS */", methods))
        compiler = shutil.which(os.environ.get("CC", "clang"))
        if not compiler:
            raise unittest.SkipTest("clang required for native preference hook tests")
        flags = ["-fobjc-exceptions", "-Wall", "-Wextra", "-Werror"]
        if platform.system() == "Darwin":
            flags += ["-fobjc-arc", "-framework", "Foundation"]
        elif shutil.which("gnustep-config"):
            flags += shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
            flags += ["-I" + subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()]
            flags += shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
        else:
            raise unittest.SkipTest("Foundation or GNUstep required")
        cls.binary = str(Path(cls.tmp.name) / "employee-prefs")
        subprocess.run([compiler, str(path), "-o", cls.binary] + flags, check=True, cwd=cls.tmp.name)

    def run_case(self, name):
        result = subprocess.run([self.binary, name], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_forced_getter_persists_without_server_setter(self):
        self.run_case("persist")

    def test_repeated_and_concurrent_reads_do_not_repeat_write(self):
        self.run_case("repeat")

    def test_each_account_uses_its_own_native_store(self):
        self.run_case("accounts")

    def test_disabled_getter_does_not_change_preference(self):
        self.run_case("disabled")

    def test_setter_can_reenter_getter_without_recursion(self):
        self.run_case("reentry")

    def test_setter_exception_does_not_disable_later_persistence(self):
        self.run_case("exception")

    def test_server_setter_and_diagnostics_keep_original_input(self):
        self.run_case("diagnostics")


if __name__ == "__main__":
    unittest.main()
