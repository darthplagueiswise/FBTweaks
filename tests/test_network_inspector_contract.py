"""Static wiring guard for the opt-in iPhone MobileConfig/Tigon inspector."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]


class NetworkInspectorContract(unittest.TestCase):
    def test_native_hooks_connect_store(self):
        fetcher = (ROOT / "src/Runtime/FBTMobileConfigFetcherCapture.mm").read_text()
        tigon = (ROOT / "src/Runtime/FBTMobileConfigTigonCapture.mm").read_text()
        self.assertIn("FBTNetworkInspectorRecordRequest", fetcher)
        self.assertIn("FBTNetworkInspectorRecordCompletion", fetcher)
        self.assertIn("FBTNetworkInspectorRecordTigon", tigon)
        self.assertIn("FBTMobileConfigTigonCaptureObserveNativeCompletion", fetcher)
        self.assertIn("F B T".replace(" ", ""), fetcher)
        self.assertIn("F B T".replace(" ", ""), tigon)

    def test_no_proxy_dependency(self):
        files = [
            ROOT / "src/Settings/FBTNetworkInspectorViewController.m",
            ROOT / "src/Runtime/FBTNetworkInspectorStore.m",
        ]
        sources = "\n".join(file.read_text() for file in files)
        self.assertNotIn("mitmproxy", sources)
        self.assertNotIn("SecTrustSetAnchorCertificates", sources)
        self.assertNotIn("https://", sources)

    def test_on_device_opt_in_and_limits(self):
        store = (ROOT / "src/Runtime/FBTNetworkInspectorStore.m").read_text()
        self.assertIn("ATOMIC_VAR_INIT(false)", store)
        self.assertIn("kMaxRequestBytes", store)
        self.assertIn("kMaxResponseBytes", store)
        self.assertIn("NSFileProtectionComplete", store)
        view = (ROOT / "src/Settings/FBTNetworkInspectorViewController.m").read_text()
        self.assertIn("FBTMCNativeProbeSetEnabled", view)
        self.assertIn("FBTNetworkInspectorSetCapturing", view)
        self.assertIn("UIActivityViewController", view)
        self.assertIn("Exportar JSONs integrais?", view)


if __name__ == "__main__":
    unittest.main()
