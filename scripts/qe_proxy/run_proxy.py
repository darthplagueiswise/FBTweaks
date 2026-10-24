#!/usr/bin/env python3
"""Start the actual local mitmdump and export only its generated public CA."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import ssl
import socket
import subprocess
import tempfile
import time


def prepare_session(directory):
    directory = Path(directory).expanduser().absolute()
    directory.mkdir(mode=0o700)  # exclusive: never reuse a CA or overwrite an export
    os.chmod(directory, 0o700)
    confdir = Path(tempfile.mkdtemp(prefix='mitmproxy-', dir=directory))
    public = directory / 'public-ca'
    public.mkdir(mode=0o700)
    return {'directory': directory, 'confdir': confdir, 'public': public, 'events': directory / 'events.jsonl'}


def proxy_command(session, executable, listen_host, listen_port, upstream_ca=None):
    command = [str(executable), '--quiet', '--listen-host', listen_host, '--listen-port', str(listen_port),
            '--set', 'confdir=' + str(session['confdir']),
            '--set', 'flow_detail=0', '--set', 'stream_large_bodies=256k',
            '--set', 'store_streamed_bodies=false',
            '--scripts', str(Path(__file__).with_name('addon.py').resolve()),
            '--set', 'qe_output=' + str(session['events'])]
    if upstream_ca is not None:
        command.extend(['--set', 'ssl_verify_upstream_trusted_ca=' + str(Path(upstream_ca).expanduser().resolve())])
    return command


def _write_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as output:
        output.write(data)


def _read_public_ca(confdir):
    source = Path(confdir) / 'mitmproxy-ca-cert.pem'
    if source.is_symlink() or source.stat().st_size > 32768:
        raise ValueError('Expected a small public certificate file')
    pem = source.read_text(encoding='ascii').strip() + '\n'
    if not re.fullmatch(r'-----BEGIN CERTIFICATE-----\n[A-Za-z0-9+/=\r\n]+\n-----END CERTIFICATE-----\n', pem):
        raise ValueError('Only a single public PEM certificate may be exported')
    der = ssl.PEM_cert_to_DER_cert(pem)
    # Decode with the standard TLS implementation to reject arbitrary base64.
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.load_verify_locations(cadata=pem)
    return pem, der


def export_public_ca(confdir, public):
    pem, der = _read_public_ca(confdir)
    fingerprint = hashlib.sha256(der).hexdigest().upper()
    fingerprint = ':'.join(fingerprint[i:i + 2] for i in range(0, len(fingerprint), 2))
    paths = {'pem': Path(public) / 'proxy-ca.pem', 'der': Path(public) / 'proxy-ca.der',
             'fingerprint': Path(public) / 'sha256.txt'}
    _write_private(paths['pem'], pem.encode('ascii'))
    _write_private(paths['der'], der)
    _write_private(paths['fingerprint'], ('SHA256 ' + fingerprint + '\n').encode('ascii'))
    return paths


def start_session(directory, executable='mitmdump', listen_host='127.0.0.1', listen_port=8080, ready_timeout=15, upstream_ca=None):
    session = prepare_session(directory)
    previous_umask = os.umask(0o077)
    try:
        # Child inherits the private umask. No raw mitmdump console logs or dumps.
        process = subprocess.Popen(proxy_command(session, executable, listen_host, listen_port, upstream_ca),
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        os.umask(previous_umask)
    try:
        deadline = time.monotonic() + ready_timeout
        source = session['confdir'] / 'mitmproxy-ca-cert.pem'
        while True:
            if source.exists():
                try:
                    _read_public_ca(session['confdir'])
                except (OSError, ValueError, ssl.SSLError):
                    pass  # A first-run file may still be in the middle of being written.
                else:
                    break
            if process.poll() is not None:
                raise RuntimeError('mitmdump exited before public CA generation; verify installation and port locally')
            if time.monotonic() >= deadline:
                raise RuntimeError('Timed out waiting for mitmdump public CA')
            time.sleep(0.05)
        # The CA is generated before mitmproxy opens the listener or starts addons.
        ready_host = {'0.0.0.0': '127.0.0.1', '::': '::1'}.get(listen_host, listen_host)
        while True:
            if process.poll() is not None:
                raise RuntimeError('mitmdump exited before listener/addon readiness')
            if session['events'].is_file():
                try:
                    with socket.create_connection((ready_host, listen_port), timeout=0.1):
                        break
                except OSError:
                    pass
            if time.monotonic() >= deadline:
                raise RuntimeError('Timed out waiting for mitmdump listener/addon readiness')
            time.sleep(0.05)
        # Only freshly generated configuration files exist in this private directory.
        for path in session['confdir'].rglob('*'):
            if not path.is_symlink():
                os.chmod(path, 0o700 if path.is_dir() else 0o600)
        paths = export_public_ca(session['confdir'], session['public'])
        return process, session, paths
    except BaseException:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, help='New private session directory on this proxy computer')
    parser.add_argument('--mitmdump', default='mitmdump', help='Installed mitmdump executable')
    parser.add_argument('--listen-host', default='127.0.0.1', help='Set the proxy computer LAN address for an authorized phone')
    parser.add_argument('--upstream-ca', help='Optional PEM CA for a controlled local upstream; TLS verification stays enabled')
    parser.add_argument('--listen-port', type=int, default=8080)
    args = parser.parse_args()
    if not 1 <= args.listen_port <= 65535:
        parser.error('listen port must be between 1 and 65535')
    try:
        process, session, paths = start_session(args.directory, args.mitmdump, args.listen_host, args.listen_port, upstream_ca=args.upstream_ca)
    except (OSError, ValueError, RuntimeError, ssl.SSLError):
        parser.exit(1, 'Proxy startup/CA export failed. Verify mitmdump, the new directory and port locally.\n')
    print(json.dumps({'public_ca': {key: str(path) for key, path in paths.items()},
                      'events': str(session['events']), 'confdir_private_do_not_share': str(session['confdir'])}), flush=True)
    try:
        return process.wait()
    except KeyboardInterrupt:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
