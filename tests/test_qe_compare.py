"""Unit tests for sanitized native/proxy A/B interpretation (no real Meta traffic)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts' / 'qe_proxy'))
import compare_profiles as module
import core


def write_fixture(path, options, status=400, eligibility=True):
    body = '&'.join(f'{k}={str(v).lower()}' for k, v in options.items()).encode()
    request = core.summarize_request('graph.prod.facebook.com', '/mobileconfig_qe_info',
                                     'POST', {'Content-Type': 'application/x-www-form-urlencoded',
                                              'Authorization': 'OAuth TEST_SECRET'}, body)
    message = 'Employee Account or Specific App Conditions' if eligibility else 'Other error'
    response = core.summarize_response(status, {'Content-Type': 'application/json'},
        json.dumps({'error': {'type': 'OAuthException', 'code': 100,
                              'message': '(#100) ' + message, 'secret': 'PRIVATE'}}).encode())
    rows = [{'event': 'request', 'local_exchange_id': 'private-opaque-id',
             'summary': request},
            {'event': 'response', 'local_exchange_id': 'private-opaque-id',
             'summary': response}]
    path.write_text('\n'.join(json.dumps(row) for row in rows) + '\n')


class ProfileCompareTests(unittest.TestCase):
    def test_true_wire_profile_still_can_receive_eligibility_400(self):
        with tempfile.TemporaryDirectory() as folder:
            a, b = Path(folder) / 'baseline.jsonl', Path(folder) / 'experimental.jsonl'
            write_fixture(a, {field: not expected for field, expected in module.EXPECTED.items()})
            write_fixture(b, module.EXPECTED)
            report = module.compare(a, b)
            self.assertTrue(report['profile_changed_on_proxy_wire'])
            self.assertTrue(report['full_metadata_observed_on_proxy_wire'])
            self.assertEqual(report['experiment']['status'], 400)
            self.assertEqual(report['experiment']['server_error'], 'eligibility')
            self.assertEqual(report['interpretation'], 'remote_eligibility_rejection_remains')
            self.assertEqual(report['server_eligibility_granted'], 'not_inferable_from_client_flags')
            output = json.dumps(report)
            self.assertNotIn('TEST_SECRET', output)
            self.assertNotIn('PRIVATE', output)
            self.assertNotIn('private-opaque-id', output)
            self.assertNotIn('credential_observation_id', output)

    def test_missing_or_unobservable_request_is_not_claimed_success(self):
        with tempfile.TemporaryDirectory() as folder:
            a, b = Path(folder) / 'native.jsonl', Path(folder) / 'proxy.jsonl'
            a.write_text('')
            write_fixture(b, {'needs_name': True}, status=200, eligibility=False)
            report = module.compare(a, b)
            self.assertFalse(report['profile_changed_on_proxy_wire'])
            self.assertFalse(report['full_metadata_observed_on_proxy_wire'])
            self.assertEqual(report['baseline']['exchange'], 'not_observed')
            self.assertEqual(report['experiment']['wire_profile'], 'not_fully_observable')

    def test_proxy_supported_hosts_and_large_native_queries(self):
        large_queries = 'x' * 95000
        body = ('queries=' + large_queries + '&needs_name=true&skip_qe=false&with_params=true').encode()
        result = core.summarize_request('graph.trunkstable.facebook.com', '/mobileconfig_qe_info',
                'POST', {'Content-Type': 'application/x-www-form-urlencoded'}, body)
        self.assertIsNotNone(result)
        self.assertEqual(result['body_shape']['kind'], 'form')
        self.assertEqual(result['body_shape']['protocol_options']['skip_qe'], False)
        self.assertNotIn(large_queries, json.dumps(result))
        self.assertIsNone(core.summarize_request('evil.graph.facebook.com',
            '/mobileconfig_qe_info', 'POST', {}, body))


if __name__ == '__main__':
    unittest.main()
