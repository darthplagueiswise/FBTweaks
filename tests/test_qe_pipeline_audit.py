"""Synthetic end-to-end QE failure regressions. No real tokens or devices."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
import qe_pipeline_audit as audit

class QEIntegratedTests(unittest.TestCase):
    def make(self,folder,name,identity,query_hash=False):
        values=[{"name":"device_id","value":identity},
                {"name":"queries","value":json.dumps(["35:1:2","1526:2:3"],separators=(",",":"))},
                {"name":"needs_name","value":"true"},{"name":"skip_qe","value":"false"},
                {"name":"access_token","value":"DO_NOT_DISCLOSE_FIXTURE"}]
        if query_hash:values.append({"name":"query_hash","value":"fixture-hash"})
        doc={"purpose":"mobileconfig_qe_info","request_method":"POST",
             "request_parameter_pairs":values,"authorization_credential_present":True,
             "known_request_headers":{"Authorization":"OAuth DO_NOT_DISCLOSE_FIXTURE"},
             "tigon_http_status":400,
             "http_response_body":{"utf8_preview":json.dumps({"error":{
                 "message":"(#100) Employee Account or Specific App Conditions",
                 "type":"OAuthException","code":100,
                 "fbtrace_id":"DO_NOT_DISCLOSE_FIXTURE"}})}}
        path=Path(folder)/name
        path.write_text(json.dumps(doc),encoding="utf-8")
        return path

    def test_integrated_pipeline_and_secret_redaction(self):
        with tempfile.TemporaryDirectory() as tmp:
            a=self.make(tmp,"a.json","device_id")
            b=self.make(tmp,"b.json","00000000-0000-0000-0000-000000000000")
            report=audit.summarize([a,b])
            self.assertEqual(report["capture_count"],2)
            self.assertTrue(report["identity_variation_did_not_change_rejection"])
            self.assertEqual(report["hashes_not_in_native_pairs"],2)
            self.assertEqual(report["remote_results"]["remote_eligibility_denied"],2)
            self.assertEqual(report["query_schema"],"valid_unique")
            raw=json.dumps(report)
            for secret in ("DO_NOT_DISCLOSE_FIXTURE","Authorization","00000000-0000-0000-0000-000000000000","35:1:2"):
                self.assertNotIn(secret,raw)
            self.assertEqual(len(json.dumps(report,separators=(",",":")).splitlines()),1)

    def test_present_hash_is_not_equated_to_authorization(self):
        with tempfile.TemporaryDirectory() as tmp:
            record=audit.one(self.make(tmp,"a.json","device_id",True))
            self.assertEqual(record["hash_states"]["query_hash"],"present")
            self.assertEqual(record["hash_states"]["one_query_hash"],"not_in_native_pairs")
            self.assertEqual(record["server_outcome"],"remote_eligibility_denied")

    def test_missing_inputs_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"bad.json"; p.write_text('{"request_parameter_pairs":"unsafe"}')
            with self.assertRaises(ValueError):audit.one(p)

    def test_one_real_proxy_exchange_joins_by_manual_window_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            record=self.make(tmp,"native.json","device_id")
            events=Path(tmp)/"events.jsonl"
            request={"event":"request","local_exchange_id":"untrusted-proxy-only",
                     "summary":{"endpoint":"mobileconfig_qe_info",
                                "body_shape":{"kind":"form","hash_fields":{
                                    "query_hash":{"state":"present","length":32},
                                    "one_query_hash":{"state":"absent","length":0}}},
                                "authorization":{"stage":"proxy_wire",
                                                 "credential_observation_id":"PRIVATE_NEVER_EXPORT"}}}
            response={"event":"response","local_exchange_id":"untrusted-proxy-only",
                      "summary":{"http_status":400,"error":{"classification":"eligibility",
                                                          "private_data":"SECRET_NEVER_EXPORT"}}}
            events.write_text(json.dumps(request)+"\n"+json.dumps(response)+"\n")
            result=audit.summarize([record],events)
            wire=result["proxy_wire"]
            self.assertEqual(wire["wire"],"observed_by_explicit_proxy")
            self.assertFalse(wire["exact_native_join"])
            self.assertEqual(wire["native_join"],"manual_capture_window_only")
            self.assertEqual(wire["post_hashes"]["query_hash"],{"state":"present","length":32})
            self.assertEqual(wire["post_hashes"]["one_query_hash"]["state"],"absent")
            self.assertEqual(result["pipeline"]["backend_wire"],"eligibility")
            data=json.dumps(result)
            for raw in ("PRIVATE_NEVER_EXPORT","SECRET_NEVER_EXPORT","untrusted-proxy-only"):
                self.assertNotIn(raw,data)

    def test_observation_labels_are_scope_correct(self):
        fetch=(ROOT/"src/Runtime/FBTMobileConfigFetcherCapture.mm").read_text()
        tigon=(ROOT/"src/Runtime/FBTMobileConfigTigonCapture.mm").read_text()
        self.assertIn("absent_in_native_pairs",fetch)
        self.assertIn("native_request_parameter_pairs_before_serialization",fetch)
        self.assertIn("not_in_url_query",tigon)
        self.assertIn("url_query_only_not_form_body",tigon)
        self.assertIn("not_verified_for_qe_info",fetch)
        self.assertNotIn('@"query_hash_state": @"not_observed"',fetch)

if __name__=="__main__":unittest.main()
