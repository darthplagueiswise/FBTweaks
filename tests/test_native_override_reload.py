"""Run the production reload bridge against controlled native API boundaries."""
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "requires macOS Foundation")
class NativeOverrideReloadTests(unittest.TestCase):
    def test_force_reload_and_incompatible_contexts(self):
        source = (ROOT / "src/Runtime/FBTNativeMobileConfigOverrides.mm").read_text()
        begin = source.index("BOOL FBTNativeMobileConfigReloadOverridesForContext(")
        end = source.index("\n}\n", begin) + 3
        with tempfile.TemporaryDirectory(prefix="fbt-native-reload-") as tmp:
            directory = Path(tmp)
            (directory / "reload.inc").write_text(source[begin:end])
            binary = directory / "reload-tests"
            subprocess.run([
                "clang++", "-std=c++11", "-fobjc-arc", "-framework", "Foundation",
                "-I", str(directory), str(ROOT / "tests/NativeOverrideReloadFixture.mm"),
                "-o", str(binary)
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
