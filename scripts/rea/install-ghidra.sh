#!/usr/bin/env bash
# Install the checksum-verified Ghidra 12.1.2 distribution outside the tweak.
set -euo pipefail
URL='https://github.com/heaven-hm/re-agent/releases/download/engine-preview-2026-10-13/ghidra_12.1.2_PUBLIC_20260605.zip'
SHA256='b62e81a0390618466c019c60d8c2f796ced2509c4c1aea4a37644a77272cf99d'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL_HOME="${REA_TOOLS_HOME:-$ROOT/.rea-tools}"
mkdir -p "$TOOL_HOME/downloads" "$TOOL_HOME/ghidra"
ZIP="$TOOL_HOME/downloads/ghidra_12.1.2_PUBLIC_20260605.zip"
if [[ ! -f "$ZIP" ]]; then
  command -v curl >/dev/null || { echo 'curl missing' >&2; exit 1; }
  curl --fail --location --retry 3 --output "$ZIP.part" "$URL"
  mv "$ZIP.part" "$ZIP"
fi
python3 - "$ZIP" "$SHA256" <<'PY'
import hashlib, sys
h=hashlib.sha256()
with open(sys.argv[1], 'rb') as f:
    for block in iter(lambda: f.read(4*1024*1024), b''): h.update(block)
if h.hexdigest()!=sys.argv[2]:
    raise SystemExit('FATAL: Ghidra archive SHA-256 mismatch: '+h.hexdigest())
print('Verified Ghidra archive SHA-256: '+h.hexdigest())
PY
command -v unzip >/dev/null || { echo 'unzip missing' >&2; exit 1; }
INSTALL="$TOOL_HOME/ghidra/ghidra_12.1.2_PUBLIC"
if [[ ! -d "$INSTALL" ]]; then
  unzip -q "$ZIP" -d "$TOOL_HOME/ghidra"
fi
test -f "$INSTALL/support/analyzeHeadless" || { echo 'Invalid Ghidra installation' >&2; exit 1; }
command -v java >/dev/null && command -v javac >/dev/null || { echo 'Full JDK 21+ required (java + javac)' >&2; exit 1; }
cat <<EOF
Ghidra installed: $INSTALL
  export GHIDRA_INSTALL_DIR="$INSTALL"
  export GHIDRA_HEADLESS_MAXMEM=6G
  rea doctor --provider ghidra --json
EOF
