#!/usr/bin/env python3
"""Check exact Shared 583 UUID, instructions and FBUserPreferences metadata.

No third-party dependencies or runtime execution. This validates the narrow
ABI used by the observer; it is not a proof of backend employee eligibility.
"""
import argparse
import json
import struct
from pathlib import Path

def verify(path):
    raw = Path(path).read_bytes()
    assert raw[:4] == b'\xcf\xfa\xed\xfe', 'expected thin Mach-O 64'
    sections, uuid = [], None
    cursor = 32
    for _ in range(struct.unpack_from('<I', raw, 16)[0]):
        cmd, size = struct.unpack_from('<II', raw, cursor)
        assert size >= 8 and cursor + size <= len(raw)
        if cmd == 0x1b:
            uuid = raw[cursor+8:cursor+24].hex()
        if cmd == 0x19:
            for i in range(struct.unpack_from('<I', raw, cursor+64)[0]):
                entry = cursor+72+i*80
                address, length, offset = struct.unpack_from('<QQI', raw, entry+32)
                sections.append((raw[entry:entry+16].split(b'\0')[0].decode(), address, length, offset))
        cursor += size
    assert uuid == '4c4c44fe55553144a1c26ccae4ed2597', 'Shared UUID mismatch'
    def offset(va):
        for _, start, length, off in sections:
            if start <= va < start + length:
                return off + va-start
        raise ValueError(hex(va))
    def ptr(va):
        value = struct.unpack_from('<Q', raw, offset(va))[0]
        return value & 0xfffffffff
    def text(va):
        off = offset(va)
        end = raw.index(b'\0', off, off+16384)
        return raw[off:end].decode()
    checks = {
        0x561d54: '00200491',  # add x0,x0,#0x108 (headers)
        0x561d58: '07f0fb97',  # branch to optional lookup
        0x45dd80: 'f30308aa',  # preserve x8 indirect result
        0x45dd8c: '7f020039',  # empty string control byte
        0x45dd90: '7f620039',  # optional disengaged at +24
        0x45ee60: '08600039',  # optional engaged at +24 after string copy
    }
    for address, expected in checks.items():
        off = offset(address)
        assert raw[off:off+4].hex() == expected, f'instruction mismatch {address:#x}'
    methods = []
    for name, start, length, _ in sections:
        if name != '__objc_classlist':
            continue
        for entry in range(start, start+length, 8):
            cp = ptr(entry)
            ro = ptr(cp+32) & ~7
            if text(ptr(ro+24)) != 'FBUserPreferences':
                continue
            ml = ptr(ro+32)
            flags, count = struct.unpack_from('<II', raw, offset(ml))
            step = 12 if flags & 0x80000000 else flags & 0xffff
            for i in range(count):
                va = ml+8+i*step
                if step == 12:
                    nr, tr, ir = struct.unpack_from('<iii', raw, offset(va))
                    sel = va+nr
                    if not flags & 0x40000000:
                        sel = ptr(sel)
                    typ, imp = va+4+tr, va+8+ir
                else:
                    sel, typ, imp = ptr(va), ptr(va+8), ptr(va+16)
                selector = text(sel)
                if selector in ('isEmployee', 'setEmployee:'):
                    methods.append((selector, text(typ), imp))
    assert ('isEmployee', 'B16@0:8', 0x6169e0) in methods
    assert ('setEmployee:', 'v20@0:8B16', 0x1ee2764) in methods
    return {'uuid': uuid, 'instruction_checks': len(checks), 'methods': [
        {'selector': name, 'encoding': typ, 'va': hex(va)} for name, typ, va in methods]}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('shared_binary')
    args = parser.parse_args()
    print(json.dumps(verify(args.shared_binary), indent=2))
