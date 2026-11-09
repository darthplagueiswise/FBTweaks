"""iOS cold-launch regression: no Objective-C or hook installations in dyld ctor."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "src" / "Tweak.x").read_text(encoding="utf-8")


class DyldBootstrapContract(unittest.TestCase):
    def test_ctor_only_schedules_c_function_on_main_queue(self):
        # Do not accidentally reintroduce the pre-main initialization abort.
        sections = SOURCE.split("%ctor {")
        self.assertEqual(len(sections), 2)
        ctor = sections[-1].split("\n}", 1)[0]
        self.assertIn("dispatch_async_f(dispatch_get_main_queue(), NULL, FBTBootstrapMainQueue)", ctor)
        for forbidden in (
            "NSUserDefaults", "%init(", "FBTRuntimeBoolClearSweep",
            "FBTInstallEntryPoints", "FBTInstallEnabledKnownFamilies",
            "FBTConfigureMobileLabEnvironment", "FBTInstallMobileConfigDebugUIBootstrap",
            "FBTInitEmployeeGroup", "FBTInstallDogfoodObserver", "FBTInstallLiquidGlassHooks",
            "objc_", "MSHookMessageEx"
        ):
            self.assertNotIn(forbidden, ctor)

    def test_original_features_survive_after_dyld(self):
        bootstrap = SOURCE.split("static void FBTBootstrapAfterDyld(void) {", 1)[1].split(
            "static void FBTBootstrapMainQueue", 1
        )[0]
        for expected in (
            "[FBTDefaults registerDefaultsOnce]",
            "FBTConfigureMobileLabEnvironment()",
            "FBTRuntimeBoolClearSweep",
            "%init(FBTHost)",
            "FBTInstallEntryPoints()",
            "FBTInstallDogfoodObserver()",
            "FBTInstallEnabledKnownFamilies()",
            "FBTInstallMobileConfigDebugUIBootstrap()",
            "FBTInstallLiquidGlassHooks()"
        ):
            self.assertIn(expected, bootstrap)

    def test_qe_oneshot_mutex_is_lazy_not_a_global_initializer(self):
        source = (Path(__file__).resolve().parents[1] /
                  "src/Runtime/FBTMobileConfigFetcherCapture.mm").read_text(encoding="utf-8")
        self.assertIn("static fbt_mc_probe::OneShot &sRequestExperiment(void)", source)
        self.assertIn("static fbt_mc_probe::OneShot instance;", source)
        self.assertNotIn("static fbt_mc_probe::OneShot sRequestExperiment;", source)
        self.assertIn("static std::mutex &sAuthReadMutex(void)", source)
        self.assertIn("static std::mutex mutex;", source)
        self.assertNotIn("static std::mutex sAuthReadMutex;", source)

    def test_post_dyld_bootstrap_is_main_only(self):
        self.assertIn("if (![NSThread isMainThread]) return;", SOURCE)
        self.assertIn("static BOOL didBootstrap = NO;", SOURCE)
        self.assertIn("dispatch_async_f(dispatch_get_main_queue(), NULL, FBTBootstrapMainQueue)", SOURCE)


if __name__ == "__main__":
    unittest.main()
