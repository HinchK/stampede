#!/usr/bin/env bash
stampede_cmd_attention() {
  local root repo="${1:-$PWD}"
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
  if [[ "$repo" == "--help" || "$repo" == "-h" ]]; then
    printf 'Usage: stampede attention [repo] [quiet|medium|loud|resume TICKET]\n'
    return 0
  fi
  [[ -d "$repo" ]] || { printf 'attention: repository not found: %s\n' "$repo" >&2; return 1; }
  shift 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$root/lib/pyenv.sh"
  resolve_python >/dev/null
  case "${1:-}" in
    quiet|medium|loud) "$PYTHON_BIN" "$root/lib/attention.py" mode "$repo" "$1" ;;
    resume) "$PYTHON_BIN" "$root/lib/attention.py" resume "$repo" "${2:-}" ;;
    '') "$PYTHON_BIN" "$root/lib/attention.py" mode "$repo" ;;
    *) printf 'attention: expected quiet, medium, loud, or resume TICKET\n' >&2; return 2 ;;
  esac
}
