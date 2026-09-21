#!/usr/bin/env bash
# tests/test_pyenv.sh — tomllib interpreter resolver suite (DOG-1)
# resolve_python(): PYTHON_BIN honouring, newest-first capability probing,
# and the actionable failure path (found version + path + remedy on stderr —
# never a ModuleNotFoundError traceback). Scratch dirs; cleans up after itself.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-pyenv-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

ok()  { printf '  ✓ [%s] %s\n' "$1" "$2"; PASS=$((PASS + 1)); }
bad() { printf '  ✗ [%s] %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
# check LABEL DESCRIPTION 'ASSERTION (eval)'
check() {
  local label="$1" desc="$2" body="$3"
  if eval "$body" >/dev/null 2>&1; then ok "$label" "$desc"; else bad "$label" "$desc"; fi
}

# shellcheck disable=SC1091  # sibling lib under test (functions only)
source "$SCRIPT_DIR/lib/pyenv.sh"

ERR="$TEST_DIR/stderr.txt"
OUT="$TEST_DIR/stdout.txt"

echo "── pyenv resolver suite (scratch: $TEST_DIR)"

# ── 1. probing resolves and exports a capable interpreter ──────────────────
check "1a" "resolve_python exports a non-empty PYTHON_BIN" \
  '[[ -n "$(unset PYTHON_BIN; resolve_python; printf "%s" "${PYTHON_BIN:-}")" ]]'
check "1b" "resolved PYTHON_BIN imports tomllib" \
  '( unset PYTHON_BIN; resolve_python; "$PYTHON_BIN" -c "import tomllib" )'

# ── 2. success is silent (stdout stays clean for eval consumers) ───────────
check "2a" "resolve_python prints nothing on success" \
  '( unset PYTHON_BIN; resolve_python ) >"$OUT" 2>"$ERR"; [[ ! -s "$OUT" && ! -s "$ERR" ]]'

# ── 3. preset capable PYTHON_BIN is honoured, not re-probed ────────────────
check "3a" "capable preset PYTHON_BIN survives resolve unchanged" \
  'PY=$(unset PYTHON_BIN; resolve_python; printf "%s" "${PYTHON_BIN:-}"); GOT=$(export PYTHON_BIN="$PY"; resolve_python; printf "%s" "${PYTHON_BIN:-}"); [[ "$GOT" == "$PY" ]]'
check "3b" "preset bare capable name is normalised to its PATH entry" \
  'PY=$(unset PYTHON_BIN; resolve_python; printf "%s" "${PYTHON_BIN:-}"); BASE=$(basename "$PY"); GOT=$(export PYTHON_BIN="$BASE"; resolve_python; printf "%s" "${PYTHON_BIN:-}"); [[ "$GOT" == "$PY" ]]'

# ── 4. preset incapable -> hard error with remedy, never a silent override ─
check "4a" "incapable preset PYTHON_BIN fails with remedy text" \
  'if ( export PYTHON_BIN=/bin/false; resolve_python ) >"$OUT" 2>"$ERR"; then false; else grep -q "tomllib" "$ERR" && grep -q "export PYTHON_BIN" "$ERR"; fi'
check "4b" "incapable preset prints nothing to stdout" \
  'if ( export PYTHON_BIN=/bin/false; resolve_python ) >"$OUT" 2>"$ERR"; then false; else [[ ! -s "$OUT" ]]; fi'
check "4c" "nonexistent preset PYTHON_BIN is named in the error" \
  'if ( export PYTHON_BIN=/nonexistent/python3; resolve_python ) 2>"$ERR"; then false; else grep -q "PYTHON_BIN=/nonexistent/python3" "$ERR" && grep -q "remedy" "$ERR"; fi'
check "4d" "incapable preset names a capable PATH candidate when one exists" \
  'HINT=$(unset PYTHON_BIN; resolve_python; printf "%s" "${PYTHON_BIN:-}"); if ( export PYTHON_BIN=/bin/false; resolve_python ) 2>"$ERR"; then false; else grep -q "$HINT" "$ERR"; fi'

# ── 5. degraded PATH: only an incapable interpreter exists ─────────────────
mkdir -p "$TEST_DIR/degraded/bin"
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/degraded/bin/python3"
chmod +x "$TEST_DIR/degraded/bin/python3"

check "5a" "degraded PATH (incapable python3 only) fails non-zero" \
  'if ( PATH="$TEST_DIR/degraded/bin:/usr/bin:/bin"; unset PYTHON_BIN; resolve_python ); then false; fi'
check "5b" "degraded failure names candidate path, tomllib, and remedy" \
  'if ( PATH="$TEST_DIR/degraded/bin:/usr/bin:/bin"; unset PYTHON_BIN; resolve_python ) 2>"$ERR"; then false; else grep -q "$TEST_DIR/degraded/bin/python3" "$ERR" && grep -q "tomllib" "$ERR" && grep -q "remedy" "$ERR"; fi'
check "5c" "degraded failure prints nothing to stdout" \
  'if ( PATH="$TEST_DIR/degraded/bin:/usr/bin:/bin"; unset PYTHON_BIN; resolve_python ) >"$OUT" 2>"$ERR"; then false; else [[ ! -s "$OUT" ]]; fi'

# ── 6. newest-first probing over a mixed PATH ───────────────────────────────
mkdir -p "$TEST_DIR/mixed/bin"
printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/mixed/bin/python3"
chmod +x "$TEST_DIR/mixed/bin/python3"
REAL=$(unset PYTHON_BIN; resolve_python; printf '%s' "${PYTHON_BIN:-}")
ln -s "$REAL" "$TEST_DIR/mixed/bin/python3.11"
ln -s "$REAL" "$TEST_DIR/mixed/bin/python3.12"

check "6a" "probe skips incapable python3, picks capable versioned name" \
  '( PATH="$TEST_DIR/mixed/bin:/usr/bin:/bin"; unset PYTHON_BIN; resolve_python; [[ "$PYTHON_BIN" == "$TEST_DIR/mixed/bin/python3.11" || "$PYTHON_BIN" == "$TEST_DIR/mixed/bin/python3.12" ]] )'
check "6b" "newest capable candidate wins (3.12 over 3.11)" \
  '( PATH="$TEST_DIR/mixed/bin:/usr/bin:/bin"; unset PYTHON_BIN; resolve_python; [[ "$PYTHON_BIN" == "$TEST_DIR/mixed/bin/python3.12" ]] )'

# ── 7. executed CLI mode (Makefile consumption) ─────────────────────────────
check "7a" "executed CLI prints a capable interpreter path" \
  'P=$(unset PYTHON_BIN; /bin/bash "$SCRIPT_DIR/lib/pyenv.sh"); [[ -x "$P" ]] && "$P" -c "import tomllib"'
check "7b" "executed CLI fails with remedy under degraded PATH" \
  'if ( unset PYTHON_BIN; PATH="$TEST_DIR/degraded/bin:/usr/bin:/bin" /bin/bash "$SCRIPT_DIR/lib/pyenv.sh" ) >"$OUT" 2>"$ERR"; then false; else [[ ! -s "$OUT" ]] && grep -q "remedy" "$ERR"; fi'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
