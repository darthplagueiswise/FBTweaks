#!/usr/bin/env bash
# Official REA CLI installed into an isolated prefix, without MCP modifications.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL_HOME="${REA_TOOLS_HOME:-$ROOT/.rea-tools}"
command -v node >/dev/null && command -v npm >/dev/null || { echo 'Node.js and npm are required' >&2; exit 1; }
node - <<'JS'
const [major,minor,patch] = process.versions.node.split('.').map(Number);
const ok = (major===22 && (minor>23 || minor===23 && patch>=4)) ||
  (major===24 && (minor>22 || minor===22 && patch>=1)) ||
  (major===26 && (minor>12 || minor===12 && patch>=1)) || major>26;
if(!ok){console.error('REA requires Node 22.23.4+, 24.22.1+, or 26.12.1+. Current: '+process.versions.node);process.exit(1);}
JS
mkdir -p "$TOOL_HOME/rea"
npm install --prefix "$TOOL_HOME/rea" --no-audit --no-fund --save-exact rea-agents@6.7.0
REA="$TOOL_HOME/rea/node_modules/.bin/rea"
"$REA" --help >/dev/null
cat <<EOF
REA installed: $REA
Use: export REA_BIN="$REA"
For MCP client integration, run "$REA" setup and review the changes.
EOF
