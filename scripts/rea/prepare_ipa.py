#!/usr/bin/env python3
"""Safely extract selected original Mach-O images from an IPA; preserve evidence."""
import argparse
import hashlib
import json
import os
import plistlib
import stat
import struct
import tempfile
import zipfile
from pathlib import Path

TARGETS = {
    'Facebook': 'Facebook',
    'FBSharedFramework': 'Frameworks/FBSharedFramework.framework/FBSharedFramework',
    'FBRarelyUsedFramework': 'Frameworks/FBRarelyUsedFramework.framework/FBRarelyUsedFramework',
    'FBReactNativeProductsFramework': 'Frameworks/FBReactNativeProductsFramework.framework/FBReactNativeProductsFramework',
    'FBSharedDynamicFramework': 'Frameworks/FBSharedDynamicFramework.framework/FBSharedDynamicFramework',
    'FBFeedAttachmentsFramework': 'Frameworks/FBFeedAttachmentsFramework.framework/FBFeedAttachmentsFramework',
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def macho_info(path):
    """Read thin Mach-O 64 header and UUID without assuming arbitrary Mach-O offsets."""
    with open(path, 'rb') as stream:
        header = stream.read(32)
        if len(header) < 32 or header[:4] not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
            raise ValueError('not a thin Mach-O 64 image: ' + str(path))
        endian = '<' if header[:4] == b'\xcf\xfa\xed\xfe' else '>'
        magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack(endian + '8I', header)
        if sizeofcmds > path.stat().st_size - 32 or ncmds > 100000:
            raise ValueError('invalid Mach-O load commands')
        commands = stream.read(sizeofcmds)
    cursor = 0
    uuid = None
    encryption = []
    for _ in range(ncmds):
        if cursor + 8 > len(commands):
            raise ValueError('truncated Mach-O load command')
        kind, length = struct.unpack_from(endian + 'II', commands, cursor)
        if length < 8 or cursor + length > len(commands):
            raise ValueError('invalid Mach-O load command length')
        if kind == 0x1b:
            if length < 24:
                raise ValueError('invalid LC_UUID')
            uuid = commands[cursor + 8:cursor + 24].hex()
        elif kind in (0x21, 0x2c):
            if length < 20:
                raise ValueError('invalid LC_ENCRYPTION_INFO')
            cryptoff, cryptsize, cryptid = struct.unpack_from(endian + 'III', commands, cursor + 8)
            encryption.append({'offset': cryptoff, 'size': cryptsize, 'cryptid': cryptid})
        cursor += length
    if cputype != 0x0100000c:
        raise ValueError('target is not ARM64: ' + hex(cputype))
    return {'cpu_type': 'arm64', 'cpu_subtype': cpusubtype, 'uuid': uuid, 'encryption': encryption,
            'encrypted': any(item['cryptid'] != 0 for item in encryption)}


def copy_member(archive, member, output, max_bytes):
    info = archive.getinfo(member)
    mode = info.external_attr >> 16
    if stat.S_ISLNK(mode):
        raise ValueError('refusing symlink inside IPA: ' + member)
    if info.is_dir() or info.file_size > max_bytes:
        raise ValueError('invalid/oversized IPA member: ' + member)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as temp:
        temporary = Path(temp.name)
        try:
            with archive.open(info) as source:
                transferred = 0
                while True:
                    chunk = source.read(4 * 1024 * 1024)
                    if not chunk:
                        break
                    transferred += len(chunk)
                    if transferred > max_bytes:
                        raise ValueError('member exceeds permitted size')
                    temp.write(chunk)
            if transferred != info.file_size:
                raise ValueError('IPA member size mismatch')
            os.replace(temporary, output)
        finally:
            temporary.unlink(missing_ok=True)


def prepare(ipa, output, expected_sha=None, names=None):
    ipa = Path(ipa).resolve()
    output = Path(output).resolve()
    if not ipa.is_file():
        raise FileNotFoundError(ipa)
    digest = sha256(ipa)
    if expected_sha and digest.lower() != expected_sha.lower():
        raise ValueError('IPA SHA-256 mismatch: expected %s, got %s' % (expected_sha, digest))
    requested = names or list(TARGETS)
    if any(name not in TARGETS for name in requested):
        raise ValueError('invalid target name')
    with zipfile.ZipFile(ipa) as archive:
        members = set(archive.namelist())
        roots = {name.split('/')[1] for name in members if name.startswith('Payload/') and '/Info.plist' in name and name.count('/') == 2 and name.endswith('.app/Info.plist')}
        if len(roots) != 1:
            raise ValueError('expected exactly one Payload/*.app/Info.plist; found ' + str(sorted(roots)))
        root = 'Payload/' + next(iter(roots)) + '/'
        with archive.open(root + 'Info.plist') as p:
            payload = p.read(8 * 1024 * 1024 + 1)
            if len(payload) > 8 * 1024 * 1024:
                raise ValueError('oversized Info.plist')
            metadata = plistlib.loads(payload)
        outputs = []
        for name in requested:
            member = root + TARGETS[name]
            if member not in members:
                continue
            dest = output / 'binaries' / name
            copy_member(archive, member, dest, 1024 * 1024 * 1024)
            outputs.append({'name': name, 'ipa_member': member, 'file': str(dest),
                            'size': dest.stat().st_size, 'sha256': sha256(dest), **macho_info(dest)})
    if not outputs:
        raise ValueError('no matching ARM64 Mach-O images in IPA')
    manifest = {'source': str(ipa), 'ipa_sha256': digest, 'bundle_identifier': metadata.get('CFBundleIdentifier'),
                'bundle_version': metadata.get('CFBundleVersion'), 'app_version': metadata.get('CFBundleShortVersionString'),
                'images': outputs, 'note': 'Original bytes only; addresses valid exclusively for matching SHA/UUID.'}
    output.mkdir(parents=True, exist_ok=True)
    destination = output / 'ipa_manifest.json'
    destination.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--expected-ipa-sha256')
    parser.add_argument('--targets', nargs='+', choices=list(TARGETS))
    args = parser.parse_args()
    report = prepare(args.ipa, args.output, args.expected_ipa_sha256, args.targets)
    print(json.dumps({'manifest': str(Path(args.output).resolve() / 'ipa_manifest.json'), 'ipa_sha256': report['ipa_sha256'], 'images': len(report['images'])}))


if __name__ == '__main__':
    main()
