#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
 echo "Usage: $0 <extraction-case-directory> <main|shared|rare|rn> [address]" >&2; exit 2
fi
case "$2" in main|shared|rare|rn) ;; *) echo "Bad module" >&2;exit 2;; esac
d="$(cd "$1" && pwd -P)"
bin="$d/$2"; test -f "$bin"
out="$d/../results/$(basename "$d")/$2"
mkdir -p "$out"
rea inspect "$bin" --provider ghidra --json > "$out/inspect.json"
rea search "$bin" MobileConfig --kind procedures --provider ghidra --json > "$out/mobileconfig.json"
if [ "$#" = 3 ];then
  rea function "$bin" --procedure="$3" --provider ghidra --json > "$out/function.json"
  rea decompile "$bin" --procedure="$3" --provider ghidra --json > "$out/decompile.json"
  rea xrefs "$bin" --address="$3" --provider ghidra --json > "$out/xrefs.json"
fi
echo "$out"
