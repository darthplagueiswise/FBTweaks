"""Behavioral privacy and endpoint tests for the opt-in proxy helper."""
import json
import os
import hashlib
import ssl
import socket
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
from urllib.parse import urlencode
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts' / 'qe_proxy'))
try:
    import core
except ModuleNotFoundError:
    core = None


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(core, 'privacy-preserving proxy core must exist')

    def request(self, **kwargs):
        values = dict(host='graph.facebook.com', path='/v20.0/mobileconfig_qe_info?access_token=SECRET',
                      method='POST', headers={'Authorization': 'Bearer SECRET', 'Content-Type': 'application/json'},
                      body=b'{"queries":{"secret_account":"SECRET"},"access_token":"SECRET"}')
        values.update(kwargs)
        return core.summarize_request(**values)

    def test_only_exact_graph_endpoints_are_observed(self):
        for path in ['/mobileconfig', '/v20.0/mobileconfigsessionless', '/mobileconfig_qe_info']:
            self.assertIsNotNone(self.request(path=path))
        for host, path in [('evil.graph.facebook.com', '/mobileconfig'),
                           ('graph.facebook.com', '/foo/mobileconfig'),
                           ('graph.facebook.com', '/mobileconfig_qe_info_extra'),
                           ('graph.facebook.com', '/mobileconfig/')]:
            self.assertIsNone(self.request(host=host, path=path))

    def test_request_summary_never_exports_values_or_unknown_keys(self):
        summary = self.request()
        encoded = json.dumps(summary)
        for secret in ['SECRET', 'secret_account', 'access_token', 'graph.facebook.com', '?']:
            self.assertNotIn(secret, encoded)
        self.assertEqual(summary['authorization'], {'present': True, 'scheme': 'bearer', 'stage': 'proxy_wire'})
        self.assertEqual(summary['body_shape']['queries'], {'kind': 'object', 'count': 1})
        self.assertEqual(summary['query_shape'], {'kind': 'form', 'fields': [], 'app_id_present': False, 'app_id_count': 0})
        self.assertTrue(summary['body_auth_field_present'])
        self.assertEqual(self.request(headers={})['authorization']['present'], False)
        self.assertEqual(self.request(headers={'authorization': ''})['authorization']['present'], True)
        self.assertEqual(self.request(headers={'AUTHORIZATION': 'SECRET'})['authorization']['scheme'], 'other')

    def test_parsing_is_bounded_and_malformed_input_has_fixed_labels(self):
        self.assertEqual(self.request(body=b'x' * 65537)['body_shape'], {'kind': 'oversize'})
        self.assertEqual(self.request(body=b'{bad SECRET')['body_shape'], {'kind': 'invalid'})
        self.assertEqual(self.request(path='/mobileconfig?' + 'x=' + 's' * 8193)['query_shape'], {'kind': 'oversize'})
        self.assertEqual(self.request(body=b'[' * 1100)['body_shape'], {'kind': 'invalid'})
        too_many = ('&'.join('x=s' for _ in range(65))).encode()
        result = self.request(headers={'content-type': 'application/x-www-form-urlencoded'}, body=too_many)
        self.assertEqual(result['body_shape'], {'kind': 'invalid'})

    def test_response_eligibility_is_classified_without_error_text(self):
        for message in ['Employee Account or Specific App Conditions', '  (#100) EMPLOYEE ACCOUNT OR SPECIFIC APP CONDITIONS  ']:
            summary = core.summarize_response(400, {'content-type': 'application/json'}, json.dumps(
                {'error': {'message': message, 'type': 'OAuthException', 'code': 100, 'fbtrace_id': 'SECRET'}}).encode())
            self.assertEqual(summary['error'], {'type': 'oauth_exception', 'code': '100', 'classification': 'eligibility'})
            self.assertNotIn('SECRET', json.dumps(summary))
        result = core.summarize_response(400, {}, b'{"error":{"message":"SECRET","type":"SECRET","code":999}}')
        self.assertEqual(result['error'], {'type': 'other', 'code': 'other', 'classification': 'unclassified'})
        self.assertNotIn('SECRET', json.dumps(result))

    def test_eligibility_rejects_negations_lookalikes_and_unrecognized_text(self):
        messages = ['This is not an Employee Account error', 'Employee Account', 'Specific App Conditions',
                    'Not Employee Account or Specific App Conditions',
                    'Employee Account or Specific App Conditions SECRET',
                    '(#1000) Employee Account or Specific App Conditions',
                    'Employee Account or Specific App Condition', 'SECRET']
        for message in messages:
            result = core.summarize_response(400, {}, json.dumps({'error': {
                'type': 'OAuthException', 'code': 100, 'message': message}}).encode())
            self.assertEqual(result['error']['classification'], 'unclassified', message)
            self.assertNotIn('SECRET', json.dumps(result))
        for error_type, code in [('other', 100), ('OAuthException', 999), ('OAuthException', '100')]:
            body = json.dumps({'error': {'type': error_type, 'code': code,
                'message': 'Employee Account or Specific App Conditions'}}).encode()
            self.assertEqual(core.summarize_response(400, {}, body)['error']['classification'], 'unclassified')

    def test_form_protocol_flags_queries_shape_and_app_context_are_redacted(self):
        options = [('needs_name', 'true'), ('skip_qe', '1'), ('api_version', '10'),
                   ('with_params', 'false'), ('with_groups', '0'), ('with_experiments', '0'),
                   ('app_id', 'SECRET_APP_A'), ('app_id', 'SECRET_APP_B'),
                   ('queries', '[{"account":"SECRET_ACCOUNT"},{"query":"SECRET_QUERY"}]'),
                   ('access_token', 'SECRET_TOKEN'), ('with_SECRET_KEY', 'true')]
        result = self.request(headers={'content-type': 'application/x-www-form-urlencoded'}, body=urlencode(options).encode())
        shape = result['body_shape']
        self.assertEqual(shape['protocol_options'], {'needs_name': True, 'skip_qe': True, 'api_version': 10,
                         'with_params': False, 'with_groups': False, 'with_experiments': False})
        self.assertEqual(shape['queries'], {'kind': 'array', 'count': 2})
        self.assertTrue(shape['app_id_present'])
        self.assertEqual(shape['app_id_count'], 2)
        self.assertTrue(result['body_auth_field_present'])
        self.assertNotIn('SECRET', json.dumps(result))

    def test_json_protocol_fields_validate_values_and_count_duplicate_app_id(self):
        raw = b'{"needs_name":"SECRET","skip_qe":false,"with_params":2,"with_groups":true,"api_version":"123456","app_id":"SECRET_A","app_id":"SECRET_B","queries":["SECRET"]}'
        result = self.request(body=raw)
        shape = result['body_shape']
        self.assertEqual(shape['protocol_options'], {'needs_name': 'invalid', 'skip_qe': False,
                         'with_params': 'invalid', 'with_groups': True, 'api_version': 'invalid'})
        self.assertEqual(shape['app_id_count'], 2)
        self.assertEqual(shape['queries'], {'kind': 'array', 'count': 1})
        self.assertFalse(result['body_auth_field_present'])
        self.assertNotIn('SECRET', json.dumps(result))
        duplicate = self.request(headers={'content-type': 'application/x-www-form-urlencoded'},
                                 body=b'needs_name=1&needs_name=0&queries=SECRET&api_version=SECRET')
        self.assertEqual(duplicate['body_shape']['protocol_options']['needs_name'], 'duplicate')
        self.assertEqual(duplicate['body_shape']['queries'], {'kind': 'invalid'})
        self.assertNotIn('SECRET', json.dumps(duplicate))

    def test_private_bounded_writer_and_local_identifiers(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'events.jsonl'
            writer = core.EventWriter(path, max_events=2, max_bytes=4096)
            for _ in range(3):
                writer.write({'event': 'request', 'summary': self.request()})
            rows = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual(len(rows), 2)
            self.assertNotEqual(rows[0]['local_event_id'], rows[1]['local_event_id'])
            self.assertTrue(rows[0]['timestamp_utc'].endswith('Z'))
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            self.assertLessEqual(path.stat().st_size, 4096)
            with self.assertRaises(FileExistsError):
                core.EventWriter(path)


class AddonTests(unittest.TestCase):
    def test_addon_records_selected_flows_without_mutating_wire_values(self):
        try:
            from addon import QECapture
        except ModuleNotFoundError:
            self.fail('read-only mitmproxy addon must exist')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'events.jsonl'
            addon = QECapture(core.EventWriter(path))
            request = SimpleNamespace(host='graph.facebook.com', path='/mobileconfig_qe_info', method='POST',
                                      headers={'authorization': 'Bearer SECRET'}, raw_content=b'{"queries":{"SECRET":1}}')
            response = SimpleNamespace(status_code=400, headers={}, raw_content=b'{"error":{"code":100,"type":"OAuthException","message":"(#100) Employee Account or Specific App Conditions"}}')
            flow = SimpleNamespace(request=request, response=response, metadata={})
            before_request = dict(vars(request))
            before_response = dict(vars(response))
            addon.request(flow)
            addon.response(flow)
            self.assertEqual(vars(request), before_request)
            self.assertEqual(vars(response), before_response)
            rows = [json.loads(x) for x in path.read_text().splitlines()]
            self.assertEqual([r['event'] for r in rows], ['request', 'response'])
            self.assertEqual(rows[0]['local_exchange_id'], rows[1]['local_exchange_id'])
            self.assertNotIn('SECRET', path.read_text())
            flow.request.host = 'example.com'
            flow.metadata = {}
            addon.request(flow)
            addon.response(flow)
            self.assertEqual(len(path.read_text().splitlines()), 2)

    def test_encoded_and_streamed_bodies_are_never_decompressed_or_invented(self):
        self.assertIsNotNone(core)
        self.assertEqual(core.summarize_response(200, {'content-encoding': 'gzip'}, b'SECRET')['body_shape'], {'kind': 'encoded'})
        self.assertEqual(core.summarize_response(200, {}, None)['body_shape'], {'kind': 'unavailable'})


class CATests(unittest.TestCase):
    def test_combined_private_key_file_is_not_exported(self):
        try:
            from run_proxy import export_public_ca
        except ModuleNotFoundError:
            self.fail('actual-proxy CA export helper must exist')
        with tempfile.TemporaryDirectory() as tmp:
            confdir = Path(tmp) / 'ca'
            confdir.mkdir()
            (confdir / 'mitmproxy-ca-cert.pem').write_text('-----BEGIN PRIVATE KEY-----\nSECRET\n-----END PRIVATE KEY-----\n')
            output = Path(tmp) / 'public'
            output.mkdir()
            with self.assertRaises(ValueError):
                export_public_ca(confdir, output)
            self.assertEqual(list(output.iterdir()), [])

    def test_public_export_keeps_certificate_fingerprint_and_excludes_private_key(self):
        from run_proxy import export_public_ca
        certificates = ssl.create_default_context().get_ca_certs(binary_form=True)
        if not certificates:
            self.skipTest('system trust store has no public certificate fixture')
        der = certificates[0]  # public test fixture only; no CA is generated by helper
        pem = ssl.DER_cert_to_PEM_cert(der)
        with tempfile.TemporaryDirectory() as tmp:
            confdir = Path(tmp) / 'ca'
            confdir.mkdir()
            (confdir / 'mitmproxy-ca-cert.pem').write_text(pem)
            (confdir / 'mitmproxy-ca.pem').write_text('SECRET PRIVATE KEY NEVER EXPORTED')
            public = Path(tmp) / 'public'
            public.mkdir()
            paths = export_public_ca(confdir, public)
            self.assertEqual(paths['der'].read_bytes(), der)
            self.assertEqual(paths['pem'].read_text(), pem)
            expected = hashlib.sha256(der).hexdigest().upper()
            self.assertEqual(paths['fingerprint'].read_text().replace(':', '').strip(), 'SHA256 ' + expected)
            for path in public.iterdir():
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                self.assertNotIn(b'SECRET', path.read_bytes())

    def test_launcher_waits_for_actual_proxy_generated_certificate_and_stops_on_timeout(self):
        from run_proxy import start_session
        certificates = ssl.create_default_context().get_ca_certs(binary_form=True)
        if not certificates:
            self.skipTest('system trust store has no public certificate fixture')
        pem = ssl.DER_cert_to_PEM_cert(certificates[0])
        with tempfile.TemporaryDirectory() as tmp:
            executable = Path(tmp) / 'fixture-mitmdump'
            # External process double: tests our process/CA boundary without TLS interception.
            program = ("#!/usr/bin/env python3\nimport pathlib,sys,time,socket\n"
                       "directory = pathlib.Path(next(x.split('=',1)[1] for x in sys.argv if x.startswith('confdir=')))\n"
                       "(directory/'mitmproxy-ca-cert.pem').touch()\n"
                       "time.sleep(0.15)\n"
                       "(directory/'mitmproxy-ca-cert.pem').write_text(" + repr(pem) + ")\n"
                       "(directory/'mitmproxy-ca.pem').write_text('SECRET PRIVATE KEY')\n"
                       "output = pathlib.Path(next(x.split('=',1)[1] for x in sys.argv if x.startswith('qe_output=')))\n"
                       "output.touch()\n"
                       "server = socket.socket(); server.bind(('127.0.0.1',int(sys.argv[sys.argv.index('--listen-port')+1]))); server.listen()\n"
                       "time.sleep(30)\n")
            executable.write_text(program)
            executable.chmod(0o700)
            with socket.socket() as probe:
                probe.bind(('127.0.0.1', 0))
                port = probe.getsockname()[1]
            process, session, paths = start_session(Path(tmp) / 'session', executable=executable, listen_port=port)
            try:
                self.assertIsNone(process.poll())
                self.assertEqual(paths['pem'].read_text(), pem)
                self.assertEqual((session['confdir'] / 'mitmproxy-ca.pem').stat().st_mode & 0o777, 0o600)
            finally:
                process.terminate()
                process.wait(timeout=2)
            executable.write_text('#!/usr/bin/env python3\nimport time\ntime.sleep(30)\n')
            with self.assertRaisesRegex(RuntimeError, 'Timed out'):
                start_session(Path(tmp) / 'timeout-session', executable=executable, ready_timeout=0.01)

    def test_session_uses_actual_mitmdump_confdir_and_private_new_directory(self):
        try:
            from run_proxy import prepare_session, proxy_command
        except ModuleNotFoundError:
            self.fail('actual-proxy launcher must exist')
        with tempfile.TemporaryDirectory() as tmp:
            session = prepare_session(Path(tmp) / 'session')
            confdir = session['confdir']
            self.assertTrue(confdir.is_dir())
            self.assertEqual(confdir.stat().st_mode & 0o777, 0o700)
            self.assertEqual(list(confdir.iterdir()), [])  # only mitmdump generates its CA
            cmd = proxy_command(session, 'mitmdump', '127.0.0.1', 8080)
            self.assertIn('confdir=' + str(confdir), cmd)
            self.assertIn('flow_detail=0', cmd)
            self.assertIn('stream_large_bodies=64k', cmd)
            self.assertIn('qe_output=' + str(session['events']), cmd)
            self.assertNotIn('ssl_insecure=true', cmd)
            self.assertNotIn('-w', cmd)
            trusted = proxy_command(session, 'mitmdump', '127.0.0.1', 8080, upstream_ca=Path(tmp) / 'fixture-ca.pem')
            self.assertIn('ssl_verify_upstream_trusted_ca=' + str(Path(tmp) / 'fixture-ca.pem'), trusted)
            with self.assertRaises(FileExistsError):
                prepare_session(Path(tmp) / 'session')


@unittest.skipUnless(os.environ.get('FBT_QE_PROXY_LIVE') == '1', 'opt-in: installed mitmproxy required')
class LiveMitmproxyTests(unittest.TestCase):
    def test_real_httpflow_addon_interface_redacts_without_mutation(self):
        from mitmproxy import connection, http
        from addon import QECapture
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'events.jsonl'
            addon = QECapture(core.EventWriter(path))
            flow = http.HTTPFlow(connection.Client(peername=('127.0.0.1', 1234), sockname=('127.0.0.1', 8080)),
                                 connection.Server(address=('graph.facebook.com', 443)))
            # In-memory fixture only: no request to Facebook is sent.
            flow.request = http.Request.make('POST', 'https://graph.facebook.com/mobileconfig_qe_info?access_token=SECRET',
                                             b'{"queries":{"SECRET":1}}', {'authorization': 'Bearer SECRET'})
            flow.response = http.Response.make(400, b'{"error":{"code":100,"type":"OAuthException","message":"(#100) Employee Account or Specific App Conditions"}}')
            request_before, response_before = flow.request.get_state(), flow.response.get_state()
            addon.request(flow)
            addon.response(flow)
            self.assertEqual(flow.request.get_state(), request_before)
            self.assertEqual(flow.response.get_state(), response_before)
            self.assertNotIn('SECRET', path.read_text())
            rows = [json.loads(x) for x in path.read_text().splitlines()]
            self.assertEqual(rows[1]['summary']['error']['classification'], 'eligibility')

    def test_real_tls_loopback_uses_own_ca_and_verifies_upstream(self):
        from datetime import datetime, timedelta, timezone
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        import http.client
        import ipaddress
        import socket
        import threading
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.x509.oid import NameOID
        from run_proxy import start_session

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Length', '2')
                self.end_headers()
                self.wfile.write(b'OK')
            def log_message(self, *args):
                pass

        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            key = ec.generate_private_key(ec.SECP256R1())
            leaf_key = ec.generate_private_key(ec.SECP256R1())
            name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Local test upstream CA')])
            now = datetime.now(timezone.utc)
            root = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
                    .serial_number(x509.random_serial_number()).not_valid_before(now - timedelta(minutes=1))
                    .not_valid_after(now + timedelta(days=1)).add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
                    .sign(key, hashes.SHA256()))
            leaf = (x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')]))
                    .issuer_name(name).public_key(leaf_key.public_key()).serial_number(x509.random_serial_number())
                    .not_valid_before(now - timedelta(minutes=1)).not_valid_after(now + timedelta(days=1))
                    .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost'), x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]), critical=False)
                    .sign(key, hashes.SHA256()))
            ca_path, cert_path, key_path = directory / 'upstream-ca.pem', directory / 'upstream.pem', directory / 'upstream.key'
            ca_path.write_bytes(root.public_bytes(serialization.Encoding.PEM))
            cert_path.write_bytes(leaf.public_bytes(serialization.Encoding.PEM))
            key_path.write_bytes(leaf_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
            key_path.chmod(0o600)
            upstream = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            server_context.load_cert_chain(cert_path, key_path)
            upstream.socket = server_context.wrap_socket(upstream.socket, server_side=True)
            thread = threading.Thread(target=upstream.serve_forever, daemon=True)
            thread.start()
            executable = Path(sys.executable).with_name('mitmdump')
            try:
                for trusted, expected_status in [(True, 200), (False, 502)]:
                    with socket.socket() as probe:
                        probe.bind(('127.0.0.1', 0))
                        port = probe.getsockname()[1]
                    process, session, paths = start_session(directory / ('trusted' if trusted else 'untrusted'),
                        executable=executable, listen_port=port, upstream_ca=ca_path if trusted else None)
                    try:
                        self.assertEqual(ssl.PEM_cert_to_DER_cert(paths['pem'].read_text()), paths['der'].read_bytes())
                        self.assertNotEqual(paths['pem'].read_bytes(), ca_path.read_bytes())
                        client_context = ssl.create_default_context(cafile=paths['pem'])
                        conn = http.client.HTTPSConnection('127.0.0.1', port, context=client_context, timeout=10)
                        conn.set_tunnel('127.0.0.1', upstream.server_port)
                        try:
                            conn.request('GET', '/mobileconfig')
                            response = conn.getresponse()
                            self.assertEqual(response.status, expected_status)
                            payload = response.read()
                            if trusted:
                                self.assertEqual(payload, b'OK')
                        finally:
                            conn.close()
                        self.assertEqual(session['events'].read_text(), '')  # loopback is not an allowed Graph host
                    finally:
                        process.terminate()
                        process.wait(timeout=5)
            finally:
                upstream.shutdown()
                upstream.server_close()
                thread.join(timeout=2)


if __name__ == '__main__':
    unittest.main()
