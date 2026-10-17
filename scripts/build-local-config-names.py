#!/usr/bin/env python3
"""Filter the supplied ID/name catalogue to IDs present in the app's v2 maps."""
import gzip, json, sys
from pathlib import Path
app, source, destination = map(Path, sys.argv[1:4])
ids = set()
for p in (app / 'mobileconfig_res').glob('*params_map*.txt'):
    data = p.read_bytes()
    if not data.startswith(b'v2,'):
        continue
    for line in data.decode().splitlines():
        if line.startswith('*'):
            fields = line.split(',')
            ids.add(int(fields[2], 16))
source_bytes = source.read_bytes()
if source_bytes.startswith(b'\x1f\x8b'):
    source_bytes = gzip.decompress(source_bytes)
result = {}
for item in json.loads(source_bytes):
    fields = item.split(':')
    if int(fields[0]) in ids:
        result[fields[0]] = {'name': fields[1], 'params': dict(zip(fields[2::2], fields[3::2]))}
destination.parent.mkdir(parents=True, exist_ok=True)
payload = json.dumps(result, separators=(',', ':'), ensure_ascii=False).encode()
destination.write_bytes(gzip.compress(payload, mtime=0))
print(json.dumps({'configs_in_build': len(ids), 'named_configs': len(result), 'gzip_bytes': destination.stat().st_size}))
