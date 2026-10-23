#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL_HOME="${REA_TOOLS_HOME:-$ROOT/.rea-tools}"
export GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-$TOOL_HOME/ghidra/ghidra_12.1.2_PUBLIC}"
export GHIDRA_HEADLESS_MAXMEM="${GHIDRA_HEADLESS_MAXMEM:-6G}"
export REA_BIN="${REA_BIN:-$TOOL_HOME/rea/node_modules/.bin/rea}"
if [[ ! -f "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]]; then
  echo "Missing Ghidra: $GHIDRA_INSTALL_DIR. Run scripts/rea/install-ghidra.sh" >&2
  exit 1
fi
exec python3 "$ROOT/scripts/rea/analyze_ipa.py" "$@"
