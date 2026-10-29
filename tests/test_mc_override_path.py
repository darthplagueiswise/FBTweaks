"""Exercise the actual Objective-C path resolver against real directory trees.

The app-group entitlement lookup and live override objects are supplied by the
fixture. Candidate selection and all filesystem checks are production code.
"""
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "requires macOS Foundation")
class OverridePathTests(unittest.TestCase):
    def test_native_directory_order_and_observed_path(self):
        source = (ROOT / "src/Runtime/FBTNativeMobileConfigOverrides.mm").read_text()
        begin = source.index("NSString *FBTNativeMobileConfigOverridesFilePath(void) {")
        end = source.index("\n}\n", begin) + 3
        with tempfile.TemporaryDirectory(prefix="fbt-path-tests-") as temporary:
            directory = Path(temporary)
            (directory / "resolver.inc").write_text(source[begin:end])
            binary = directory / "path-tests"
            subprocess.run([
                "clang++", "-std=c++11", "-fobjc-arc", "-framework", "Foundation",
                "-I", str(directory), str(ROOT / "tests/OverridePathFixture.mm"),
                "-o", str(binary)
            ], check=True, capture_output=True, text=True)
            run = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("PASS override path cases", run.stdout)


if __name__ == "__main__":
    unittest.main()
