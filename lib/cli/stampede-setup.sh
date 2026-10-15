#!/usr/bin/env bash
# Guided first-run setup delegates text and TOML handling to the Python
# interpreter already required by Stampede's config parser.
stampede_cmd_setup() {
  local root py
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  # shellcheck source=/dev/null
  source "$root/lib/pyenv.sh"
  resolve_python >/dev/null
  py="$PYTHON_BIN"
  "$py" "$root/lib/setup.py" "$root" "$@"
}
