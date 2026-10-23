#!/usr/bin/env python3
"""Run REA+Ghidra read-only analysis on extracted IPA images and selected XREFs."""
import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from prepare_ipa import prepare, sha256, TARGETS


def invoke(command, destination, timeout):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix(destination.suffix + '.partial')
    try:
        with temp.open('w') as output:
            result = subprocess.run(command, stdout=output, stderr=subprocess.PIPE, text=True,
                                    timeout=timeout, check=False)
        if result.returncode != 0:
            temp.unlink(missing_ok=True)
            return {'ok': False, 'command': command, 'exit_code': result.returncode, 'error': result.stderr[-3000:]}
        data = json.loads(temp.read_text())
        if isinstance(data, dict) and (data.get('isError') is True or data.get('ok') is False or data.get('status') == 'error'):
            raise ValueError('REA reported an error object: ' + str(data)[:1000])
        temp.replace(destination)
        return {'ok': True, 'command': command, 'output': str(destination)}
    except (subprocess.TimeoutExpired, ValueError, json.JSONDecodeError) as error:
        temp.unlink(missing_ok=True)
        return {'ok': False, 'command': command, 'error': str(error)}


def analyze(args):
    output = Path(args.output).resolve()
    repo = Path(__file__).resolve().parents[2]
    if output == repo or repo in output.parents:
        raise ValueError('use a dedicated output folder OUTSIDE the Git checkout')
    previous = output / 'ipa_manifest.json'
    previous_manifest = json.loads(previous.read_text()) if args.resume and previous.is_file() else None
    if previous_manifest and previous_manifest.get('ipa_sha256') != sha256(args.ipa):
        raise ValueError('cannot --resume: output directory belongs to a different IPA SHA-256')
    manifest = prepare(args.ipa, output, args.expected_ipa_sha256, args.targets)
    if previous_manifest and args.resume:
        earlier = {image['name']: image['sha256'] for image in previous_manifest.get('images', [])}
        for image in manifest['images']:
            if image['name'] in earlier and earlier[image['name']] != image['sha256']:
                raise ValueError('cannot --resume: binary SHA-256 changed for ' + image['name'])
    rea = args.rea or os.environ.get('REA_BIN') or 'rea'
    if not (Path(rea).is_file() or shutil.which(rea)):
        raise RuntimeError('REA CLI not found. Install it and export REA_BIN or add rea to PATH.')
    if not os.environ.get('GHIDRA_INSTALL_DIR'):
        raise RuntimeError('export GHIDRA_INSTALL_DIR pointing at extracted Ghidra 12.1.x before analysis')
    actions = []
    timeout = args.timeout
    doctor = invoke([rea, 'doctor', '--provider', 'ghidra', '--json'], output / 'rea' / 'doctor.json', timeout)
    actions.append(doctor)
    if not doctor['ok']:
        raise RuntimeError('REA doctor failed: ' + str(doctor.get('error', 'check log')))
    targets = {}
    if args.addresses:
        data = json.loads(Path(args.addresses).read_text())
        for target in data.get('targets', []):
            if not target.get('name') or target['name'] not in TARGETS or not isinstance(target.get('addresses'), list):
                raise ValueError('invalid targets/address schema')
            if target['name'] in targets:
                raise ValueError('duplicate target name: ' + target['name'])
            targets[target['name']] = target
    for item in manifest['images']:
        name, path = item['name'], item['file']
        folder = output / 'rea' / name
        if item['encrypted']:
            actions.append({'ok': False, 'skipped': True, 'name': name, 'reason': 'LC_ENCRYPTION_INFO cryptid != 0'})
            continue
        inspection = folder / 'inspect.json'
        if args.resume and inspection.is_file():
            try:
                json.loads(inspection.read_text())
                actions.append({'ok': True, 'resumed': True, 'output': str(inspection)})
            except json.JSONDecodeError:
                actions.append(invoke([rea, 'inspect', path, '--provider', 'ghidra', '--json'], inspection, timeout))
        else:
            actions.append(invoke([rea, 'inspect', path, '--provider', 'ghidra', '--json'], inspection, timeout))
        target = targets.get(name)
        if not target:
            continue
        fingerprint = (target.get('sha256') == item['sha256'] if target.get('sha256') else
                       target.get('uuid', '').lower() == (item['uuid'] or '').lower() if target.get('uuid') else False)
        if not fingerprint:
            actions.append({'ok': False, 'skipped': True, 'name': name,
                            'reason': 'address seeds rejected: no matching SHA-256/UUID'})
            continue
        for address in target['addresses']:
            if not isinstance(address, str) or not address.lower().startswith('0x') or not address[2:] or not all(c in '0123456789abcdef' for c in address[2:].lower()):
                raise ValueError('address must be hexadecimal with 0x prefix')
            for operation in ('function', 'decompile', 'xrefs', 'instructions'):
                dest = folder / (operation + '_' + address.lower() + '.json')
                if args.resume and dest.is_file():
                    try:
                        json.loads(dest.read_text())
                        actions.append({'ok': True, 'resumed': True, 'output': str(dest)})
                        continue
                    except json.JSONDecodeError:
                        pass
                actions.append(invoke([rea, operation, path, address, '--provider', 'ghidra', '--json'], dest, timeout))
    report = {'time_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'ipa_sha256': manifest['ipa_sha256'], 'provider': 'ghidra',
              'rea_bin': rea, 'ghidra_install_dir': os.environ['GHIDRA_INSTALL_DIR'],
              'actions': actions, 'success': sum(bool(x.get('ok')) for x in actions),
              'failure': sum(not x.get('ok') and not x.get('skipped') for x in actions),
              'skipped': sum(bool(x.get('skipped')) for x in actions)}
    (output / 'rea_run.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'report': str(output / 'rea_run.json'), 'success': report['success'],
                      'failure': report['failure'], 'skipped': report['skipped']}))
    return 1 if report['failure'] else 0


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ipa', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--expected-ipa-sha256')
    p.add_argument('--targets', nargs='+', choices=list(TARGETS))
    p.add_argument('--addresses', help='JSON target list; each address list requires matching SHA-256 or UUID')
    p.add_argument('--rea', help='REA executable')
    p.add_argument('--timeout', type=int, default=1800)
    p.add_argument('--resume', action='store_true')
    a = p.parse_args()
    try:
        sys.exit(analyze(a))
    except (ValueError, RuntimeError, FileNotFoundError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
