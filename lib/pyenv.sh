#!/usr/bin/env bash
# lib/pyenv.sh — tomllib-capable interpreter resolver (DOG-1)
#
# Every Python entry point in the swarm resolves through resolve_python(),
# because macOS ships /usr/bin/python3 = 3.9 while tomllib is 3.11+: a bare
# `python3` breaks config parsing wherever /usr/bin wins the PATH race.
#
# Contract:
#   - $PYTHON_BIN already set: honoured strictly. Capable -> exported
#     (normalised to its absolute path when possible). Incapable or missing
#     -> hard error with remedy: an explicit choice is never silently
#     overridden (fail-closed, same bar as lib/profile.sh).
#   - unset: probe python3.14 python3.13 python3.12 python3.11 python3
#     (newest first); the first that imports tomllib wins and is exported.
#   - success is silent (safe for `eval` consumers); failure prints the found
#     version, its path, and a remedy to stderr, then returns 1 — never a
#     ModuleNotFoundError traceback.
#
# Usage:
#   sourced:   source lib/pyenv.sh; resolve_python; ... "$PYTHON_BIN" ...
#   executed:  bash lib/pyenv.sh
#              Prints the resolved path (exit 1 + remedy on stderr when
#              nothing qualifies) — built for command-substitution consumers
#              such as the Makefile lint recipe.

set -euo pipefail

# Capability probe: behaviour, not version parsing — the interpreter must
# actually import tomllib right now.
_pyenv_capable() { # CANDIDATE
  "$1" -c 'import tomllib' >/dev/null 2>&1
}

# Best-effort version string for the error path; never fails its caller.
_pyenv_version() { # CANDIDATE
  "$1" -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || printf 'unknown'
}

# Remedy line; names a capable PATH candidate as the export target when one
# exists, else points at brew / an explicit export.
_pyenv_remedy() { # HINT ("" when no capable candidate is on PATH)
  if [[ -n "$1" ]]; then
    printf 'pyenv: remedy: export PYTHON_BIN=%s (capable interpreter found on PATH)\n' "$1"
  else
    printf 'pyenv: remedy: brew install python@3.12, or export PYTHON_BIN=/path/to/python3.11+\n'
  fi
}

resolve_python() {
  # Explicit choice: honour it, never override it.
  if [[ -n "${PYTHON_BIN:-}" ]]; then
    if _pyenv_capable "$PYTHON_BIN"; then
      local resolved
      resolved=$(command -v "$PYTHON_BIN" 2>/dev/null || printf '%s' "$PYTHON_BIN")
      PYTHON_BIN=$resolved
      export PYTHON_BIN
      return 0
    fi
    local hint=""
    local cand
    for cand in python3.14 python3.13 python3.12 python3.11 python3; do
      if command -v "$cand" >/dev/null 2>&1 && _pyenv_capable "$cand"; then
        hint=$(command -v "$cand")
        break
      fi
    done
    printf 'pyenv: PYTHON_BIN=%s (Python %s) cannot import tomllib — Python >= 3.11 required\n' \
      "$PYTHON_BIN" "$(_pyenv_version "$PYTHON_BIN")" >&2
    _pyenv_remedy "$hint" >&2
    return 1
  fi

  # No explicit choice: probe newest-first, remember every incapable hit.
  local tried="" cand path
  for cand in python3.14 python3.13 python3.12 python3.11 python3; do
    command -v "$cand" >/dev/null 2>&1 || continue
    path=$(command -v "$cand")
    if _pyenv_capable "$path"; then
      PYTHON_BIN=$path
      export PYTHON_BIN
      return 0
    fi
    tried+="  pyenv: tried ${cand} -> ${path} (Python $(_pyenv_version "$path")): cannot import tomllib"$'\n'
  done

  printf 'pyenv: no tomllib-capable Python interpreter found — Python >= 3.11 required\n' >&2
  if [[ -n "$tried" ]]; then
    printf '%s' "$tried" >&2
  fi
  _pyenv_remedy "" >&2
  return 1
}

# Executed (not sourced): resolve and print the path. Sourcing defines the
# functions only — preflight must stay free to call resolve_python
# conditionally and record the failure itself instead of dying.
if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  resolve_python
  printf '%s\n' "$PYTHON_BIN"
fi
