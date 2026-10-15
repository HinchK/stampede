#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$ROOT/lib/pyenv.sh"
resolve_python >/dev/null
"$PYTHON_BIN" "$ROOT/tests/test_attention.py"
