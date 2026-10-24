"""Hash-path audit must distinguish QE native arguments from MobileConfig sync hashes."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "audit-qe-hash-capture.py"
spec = importlib.util.spec_from_file_location("qe_hash_audit", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class QEHashPathTests(unittest.TestCase):
    def sample(self):
        return {
            "purpose": "mobileconfig_qe_info",
            "request_source": "asyncFetch_parameters_before_Tigon_request_builder",
            "request_parameter_pairs": [
                {"name": "device_id", "value": "device_id"},
                {"name": "queries", "value": '["12:1","13:4"]'},
                {"name": "needs_name", "value": "true"},
                {"name": "skip_qe", "value": "false"},
                {"name": "access_token", "value": "NEVER_EXPORT_THIS_SECRET"}
            ],
            "known_request_headers": {"Authorization": "OAuth NEVER_EXPORT_THIS_SECRET"},
            "tigon_http_status": 400,
            "http_response_body": {"utf8_preview": json.dumps({"error": {
                "code": 100, "type": "OAuthException", "message": "Employee Account or Specific App Conditions"
            }})}
        }

    def test_absent_hash_fields_not_misreported_as_generated(self):
        d = module.audit_capture(self.sample())
        self.assertEqual(d["native_pair_count"], 5)
        self.assertEqual(d["query_count"], 2)
        self.assertFalse(d["query_hash_in_native_args"])
        self.assertFalse(d["one_query_hash_in_native_args"])
        self.assertEqual(d["request_data_query_hash_sync_state"], "not_determined_by_qe_info")
        self.assertEqual(d["device_id_format"], "field_name_literal")
        self.assertEqual(d["server_error_class"], "oauth_exception_100_eligibility")
        self.assertEqual(d["wire_hash_presence"], "not_established_from_native_capture")
        self.assertNotIn("NEVER_EXPORT_THIS_SECRET", json.dumps(d))

    def test_hash_present_separately_and_duplicates_detected(self):
        doc = self.sample()
        doc["request_parameter_pairs"] += [
            {"name": "query_hash", "value": "not_proven"},
            {"name": "one_query_hash", "value": "not_proven"},
            {"name": "query_hash", "value": "duplicate"}
        ]
        d = module.audit_capture(doc)
        self.assertEqual(d["query_hash_count"], 2)
        self.assertFalse(d["query_hash_in_native_args"])
        self.assertTrue(d["one_query_hash_in_native_args"])

    def test_bundle_hash_format_does_not_imply_endpoint_parameter(self):
        with tempfile.TemporaryDirectory() as folder:
            ipa = Path(folder) / "fake.ipa"
            with ZipFile(ipa, "w") as z:
                z.writestr(module.RESOURCE, "f" * 64)
            self.assertEqual(module.bundle_hash_state(ipa), "bundle_resource_present_64hex")
            doc = module.audit_capture(self.sample(), module.bundle_hash_state(ipa))
            self.assertFalse(doc["one_query_hash_in_native_args"])
            with ZipFile(ipa, "w") as z:
                z.writestr(module.RESOURCE, "untrusted")
            self.assertEqual(module.bundle_hash_state(ipa), "bundle_resource_invalid_length")

    def test_cli_minified_and_no_oauth_leak(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "request.json"
            source.write_text(json.dumps(self.sample()), encoding="utf-8")
            proc = subprocess.run([sys.executable, str(SCRIPT), str(source)],
                                  check=True, capture_output=True, text=True)
            lines = proc.stdout.splitlines()
            self.assertEqual(len(lines), 1)
            self.assertEqual(lines[0], json.dumps(json.loads(lines[0]),
                                                 ensure_ascii=False, sort_keys=True, separators=(",", ":")))
            self.assertNotIn("NEVER_EXPORT_THIS_SECRET", proc.stdout)
            self.assertNotIn("Authorization", proc.stdout)

    def test_runtime_source_no_hash_injection(self):
        src = (ROOT / "src" / "Runtime" / "FBTMobileConfigFetcherCapture.mm").read_text()
        self.assertIn('"absent_in_native_arguments"', src)
        self.assertIn('FBTMCOneQueryBundleHashState()', src)
        self.assertNotIn('emplace_back("query_hash",', src)
        self.assertNotIn('emplace_back("one_query_hash",', src)


if __name__ == "__main__":
    unittest.main()
