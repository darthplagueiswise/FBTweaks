#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export THEOS="${THEOS:-$HOME/theos}"
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless "$@"
