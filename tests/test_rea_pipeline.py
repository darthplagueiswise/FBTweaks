"""REA/Ghidra IPA preparation and runner contract tests, without proprietary binaries."""
import hashlib
import json
import os
import plistlib
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

DIR = Path(__file__).resolve().parents[1] / 'scripts' / 'rea'
sys.path.insert(0, str(DIR))
from prepare_ipa import prepare, macho_info

UUID = bytes.fromhex('0123456789abcdeffedcba9876543210')


def fake_macho(encrypted=False):
    # Only a header fixture, NOT working machine code or Ghidra proof.
    commands = struct.pack('<II', 0x1b, 24) + UUID
    if encrypted:
        commands += struct.pack('<IIIII', 0x2c, 24, 0, 1024, 1) + struct.pack('<I', 0)
    header = struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 2, 1 + int(encrypted), len(commands), 0, 0)
    return header + commands + b'EXAMPLE ONLY'


def make_fixture(root):
    ipa = root / 'fixture.ipa'
    with zipfile.ZipFile(ipa, 'w') as z:
        z.writestr('Payload/Facebook.app/Info.plist', plistlib.dumps({
            'CFBundleIdentifier': 'com.facebook.ota', 'CFBundleVersion': '123',
            'CFBundleShortVersionString': '583.0.0'}))
        z.writestr('Payload/Facebook.app/Facebook', fake_macho())
        z.writestr('Payload/Facebook.app/Frameworks/FBSharedFramework.framework/FBSharedFramework', fake_macho())
    return ipa


def fake_rea(root):
    binary = root / 'rea'
    binary.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps({"operation":sys.argv[1],"ok":True}))\n')
    binary.chmod(0o755)
    return binary


class PipelineTests(unittest.TestCase):
    def test_macho_uuid_and_encryption(self):
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp)/'macho'
            binary.write_bytes(fake_macho())
            self.assertEqual(macho_info(binary)['uuid'], UUID.hex())
            self.assertFalse(macho_info(binary)['encrypted'])
            binary.write_bytes(fake_macho(True))
            self.assertTrue(macho_info(binary)['encrypted'])

    def test_original_bytes_hashes_and_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ipa = make_fixture(root)
            data = prepare(ipa, root/'out')
            self.assertEqual(len(data['images']), 2)
            self.assertEqual(data['ipa_sha256'], hashlib.sha256(ipa.read_bytes()).hexdigest())
            self.assertEqual((root/'out'/'binaries'/'Facebook').read_bytes(), fake_macho())
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                prepare(ipa, root/'other', '0'*64)

    def test_symlink_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ipa = make_fixture(root)
            with zipfile.ZipFile(ipa, 'a') as z:
                entry = zipfile.ZipInfo('Payload/Facebook.app/Frameworks/FBRarelyUsedFramework.framework/FBRarelyUsedFramework')
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                z.writestr(entry, '/tmp/evil')
            with self.assertRaisesRegex(ValueError, 'refusing symlink'):
                prepare(ipa, root/'out')

    def test_runner_decompile_xrefs_and_uuid_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ipa = make_fixture(root)
            rea = fake_rea(root)
            target = root/'addresses.json'
            target.write_text(json.dumps({'targets': [
                {'name': 'Facebook', 'uuid': UUID.hex(), 'addresses': ['0x1000']},
                {'name': 'FBSharedFramework', 'uuid': '0'*32, 'addresses': ['0x1000']}
            ]}))
            env = dict(os.environ, GHIDRA_INSTALL_DIR=str(root), REA_BIN=str(rea))
            command = [sys.executable, str(DIR/'analyze_ipa.py'), '--ipa', str(ipa), '--output', str(root/'out'),
                       '--addresses', str(target)]
            p = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)
            report = json.loads((root/'out'/'rea_run.json').read_text())
            self.assertEqual(report['success'], 7)
            self.assertEqual(report['skipped'], 1)
            self.assertTrue((root/'out'/'rea'/'Facebook'/'decompile_0x1000.json').exists())
            self.assertFalse((root/'out'/'rea'/'FBSharedFramework'/'decompile_0x1000.json').exists())
            second = subprocess.run(command+['--resume'], env=env, capture_output=True, text=True)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertTrue(any(x.get('resumed') for x in json.loads((root/'out'/'rea_run.json').read_text())['actions']))

    def test_resume_rejects_different_ipa(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ipa = make_fixture(root)
            command = [sys.executable, str(DIR/'analyze_ipa.py'), '--ipa', str(ipa), '--output', str(root/'out')]
            env = dict(os.environ, GHIDRA_INSTALL_DIR=str(root), REA_BIN=str(fake_rea(root)))
            self.assertEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)
            manifest = (root/'out'/'ipa_manifest.json').read_bytes()
            with zipfile.ZipFile(ipa, 'a') as z:
                z.writestr('Payload/Facebook.app/changed.txt', 'changed')
            p = subprocess.run(command+['--resume'], env=env, capture_output=True, text=True)
            self.assertEqual(p.returncode, 2)
            self.assertIn('different IPA', p.stderr)
            self.assertEqual((root/'out'/'ipa_manifest.json').read_bytes(), manifest)

    def test_missing_rea_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            p = subprocess.run([sys.executable, str(DIR/'analyze_ipa.py'), '--ipa', str(make_fixture(root)),
                                '--output', str(root/'out'), '--rea', str(root/'missing')],
                               env=dict(os.environ, GHIDRA_INSTALL_DIR='fake'), capture_output=True, text=True)
            self.assertEqual(p.returncode, 2)
            self.assertIn('REA CLI not found', p.stderr)

    def test_output_in_checkout_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            p = subprocess.run([sys.executable, str(DIR/'analyze_ipa.py'), '--ipa', str(make_fixture(root)),
                                '--output', str(DIR/'private_evidence')],
                               capture_output=True, text=True)
            self.assertEqual(p.returncode, 2)
            self.assertIn('OUTSIDE the Git checkout', p.stderr)


if __name__ == '__main__':
    unittest.main()
