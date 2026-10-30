"""Contract for dyld-safe cold-start in an injected Facebook IPA."""
from pathlib import Path
import unittest

SRC = (Path(__file__).resolve().parents[1] / "src/Tweak.x").read_text()


class ColdStartBootstrapTests(unittest.TestCase):
    def test_no_hook_install_inside_dyld_constructor(self):
        ctor = SRC.split("%ctor {", 1)[1]
        scheduled = ctor.index("dispatch_async(dispatch_get_main_queue(), ^{")
        before = ctor[:scheduled]
        for name in (
            "%init(FBTHost);",
            "FBTInstallEntryPoints();",
            "FBTInstallDogfoodObserver();",
            "FBTInstallEnabledKnownFamilies();",
            "FBTRuntimeBoolClearSweep(",
            "FBTInstallLiquidGlassHooks();",
            "FBTInstallMobileConfigDebugUIBootstrap();",
        ):
            self.assertNotIn(name, before, name)
            self.assertIn(name, ctor[scheduled:], name)

    def test_launch_latched_env_remains_before_deferred_hooks(self):
        ctor = SRC.split("%ctor {", 1)[1]
        self.assertLess(ctor.index("FBTConfigureMobileLabEnvironment();"),
                        ctor.index("dispatch_async(dispatch_get_main_queue(), ^{"))
        self.assertLess(ctor.index("dispatch_async(dispatch_get_main_queue(), ^{"),
                        ctor.index("%init(FBTHost);"))

    def test_post_launch_retry_existing(self):
        self.assertIn("FBTRetryEntryPoints();", SRC)
        self.assertIn("FBTInstallEnabledKnownFamilies();", SRC)


if __name__ == "__main__":
    unittest.main()
