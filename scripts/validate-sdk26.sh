#!/usr/bin/env bash
# Compatibility entrypoint. SDK 27.1 is the only build target.
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/validate-sdk27.sh" "$@"
