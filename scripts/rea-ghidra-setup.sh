#!/usr/bin/env bash
set -euo pipefail
root="$HOME/.local/share/fbt-re-tools"
mkdir -p "$root"
for exe in node npm java javac curl unzip python3 ps; do
  command -v "$exe" >/dev/null || { echo "Missing: $exe" >&2; exit 1; }
done
node - <<'NODE'
const [major,minor,patch]=process.versions.node.split(".").map(Number);
const ok=major===22&&(minor>23||(minor===23&&patch>=4))||
  major===24&&(minor>22||(minor===22&&patch>=1))||
  major===26&&(minor>12||(minor===12&&patch>=1));
if (!ok) { console.error("REA requires newer Node: "+process.version); process.exit(1); }
NODE
name=ghidra_12.1.2_PUBLIC_20260605.zip
zip="$root/$name"
ghidra="$root/ghidra_12.1.2_PUBLIC"
if [ ! -f "$ghidra/support/analyzeHeadless" ]; then
  if [ ! -f "$zip" ]; then
    curl -fL --retry 3 "https://github.com/heaven-hm/re-agent/releases/download/engine-preview-2026-10-13/$name" -o "$zip.part"
    mv "$zip.part" "$zip"
  fi
  python3 - "$zip" <<'PY'
import hashlib,sys
with open(sys.argv[1],"rb") as f: got=hashlib.file_digest(f,"sha256").hexdigest()
want="b62e81a0390618466c019c60d8c2f796ced2509c4c1aea4a37644a77272cf99d"
if got!=want: raise SystemExit("Ghidra archive hash mismatch "+got)
print("Verified Ghidra archive",got)
PY
  unzip -q "$zip" -d "$root"
fi
test -f "$ghidra/support/analyzeHeadless"
npm install --prefix "$root/npm" --no-audit --no-fund rea-agents@6.7.0
printf 'export GHIDRA_INSTALL_DIR="%s"\nexport GHIDRA_HEADLESS_MAXMEM=4G\nexport PATH="%s/npm/node_modules/.bin":$PATH\n' "$ghidra" "$root" > "$root/env.sh"
source "$root/env.sh"
rea doctor --provider ghidra --json
echo "Run: source $root/env.sh"
