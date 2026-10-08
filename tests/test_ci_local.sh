#!/usr/bin/env bash
# tests/test_ci_local.sh — scripts/ci-local.sh suite (DOG-18)
# Hermetic: fixture tree + stubbed make/shellcheck (args logged, rc scripted);
# the real repo's ci.yml is exercised read-only for pin parsing. Zero network,
# real `make check` never runs.
#
# shellcheck disable=SC2016  # assertion bodies are single-quoted eval strings
set -euo pipefail

TEST_DIR=$(mktemp -d /tmp/test-cilocal-$$-XXXX)
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SCRIPT="$SCRIPT_DIR/scripts/ci-local.sh"
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

STATE="$TEST_DIR/state"; mkdir -p "$STATE"

# Stub make: logs its args, exits with $STATE/MAKE_RC (default 0).
BIN="$TEST_DIR/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\nprintf '"'"'%%s\\n'"'"' "$*" >> "%s/MAKE_ARGS"\nrc=0\n[ -f "%s/MAKE_RC" ] && rc=$(cat "%s/MAKE_RC")\nexit "$rc"\n' \
  "$STATE" "$STATE" "$STATE" > "$BIN/make"
# Stub shellcheck: answers --version from $STATE/SC_VER (default 0.0.0).
printf '#!/bin/sh\n[ "$1" = --version ] || exit 9\nprintf '"'"'ShellCheck - shell script analysis tool\\nversion: %%s\\n'"'"' "$(cat "%s/SC_VER" 2>/dev/null || echo 0.0.0)"\nexit 0\n' \
  "$STATE" > "$BIN/shellcheck"
chmod +x "$BIN/make" "$BIN/shellcheck"

# Fixture tree: the script resolves ROOT from its own location, so a copied
# script + a fixture ci.yml exercise the real logic against a controlled pin.
FR="$TEST_DIR/fix"; mkdir -p "$FR/scripts" "$FR/.github/workflows"
cp "$SCRIPT" "$FR/scripts/ci-local.sh" && chmod +x "$FR/scripts/ci-local.sh"
printf 'name: CI\njobs:\n  check:\n    steps:\n      - env:\n          SC_VERSION: "v9.9.9"\n' \
  > "$FR/.github/workflows/ci.yml"

FX="$FR/scripts/ci-local.sh"

# Run harness: OUT/ERR/RC reflect one invocation under the stub PATH.
run() { # SCRIPT_PATH [args...]
  OUT=$(PATH="$BIN:/usr/bin:/bin" "$1" "${@:2}" 2>"$STATE/err") && RC=0 || RC=$?
  ERR=$(cat "$STATE/err")
}

echo "── ci-local suite (scratch: $TEST_DIR)"

# ── 1. Parity reporting and gate delegation ────────────────────────────────
printf '9.9.9\n' > "$STATE/SC_VER"
run "$FX"
check 1a  "match: exits 0 with parity line" \
  '[[ $RC -eq 0 ]] && grep -q "shellcheck parity: local 9.9.9 == CI pin v9.9.9" <<<"$OUT"'
check 1b  "delegates to make -C <root> check, nothing else" \
  '[[ $(tail -n1 "$STATE/MAKE_ARGS") == "-C '"$FR"' check" ]]'
printf '0.8.0\n' > "$STATE/SC_VER"
run "$FX"
check 1c  "mismatch: default warns, still exits with make rc 0" \
  '[[ $RC -eq 0 ]] && grep -q "local shellcheck 0.8.0 != CI pin v9.9.9" <<<"$ERR"'
check 1d  "mismatch warning names the authoritative gate" \
  'grep -q "authoritative" <<<"$ERR"'
run "$FX" --strict
check 1e  "mismatch: --strict fails after a green gate" \
  '[[ $RC -eq 1 ]] && grep -q -- "--strict" <<<"$ERR"'
printf '7\n' > "$STATE/MAKE_RC"
run "$FX"
check 1f  "gate failure propagates make rc verbatim (default)" '[[ $RC -eq 7 ]]'
run "$FX" --strict
check 1g  "gate failure propagates make rc verbatim (--strict, beats parity)" \
  '[[ $RC -eq 7 ]]'
rm -f "$STATE/MAKE_RC"

# ── 2. Degrade cases ───────────────────────────────────────────────────────
# Hermetic absence (CI-FIX-1): PATH is ONLY a scratch bin dir — the stub make
# plus symlinks to the externals ci-local.sh resolves. No system dir is
# whitelisted, so the real shellcheck is unreachable wherever the host
# installed it (/usr/bin on ubuntu runners, Homebrew on macOS).
BIN_NOSC="$TEST_DIR/bin-nosc"; mkdir -p "$BIN_NOSC"
cp "$BIN/make" "$BIN_NOSC/make"
for tool in bash git sed awk head cat dirname; do
  ln -s "$(command -v "$tool")" "$BIN_NOSC/$tool"
done
OUT=$(PATH="$BIN_NOSC" "$FX" 2>"$STATE/err") && RC=0 || RC=$?
ERR=$(cat "$STATE/err")
check 2a  "shellcheck absent: warns, exits 0 after green gate" \
  '[[ $RC -eq 0 ]] && grep -q "shellcheck not on PATH" <<<"$ERR"'
OUT=$(PATH="$BIN_NOSC" "$FX" --strict 2>"$STATE/err") && RC=0 || RC=$?
check 2b  "shellcheck absent: --strict fails" '[[ $RC -eq 1 ]]'
printf 'name: CI\njobs:\n  check:\n    steps:\n      - run: make check\n' \
  > "$FR/.github/workflows/ci.yml"
run "$FX"
check 2c  "no SC_VERSION pin: warns, exits 0" \
  '[[ $RC -eq 0 ]] && grep -q "no SC_VERSION pin" <<<"$ERR"'
run "$FX" --strict
check 2d  "no SC_VERSION pin: --strict fails (parity unverifiable)" \
  '[[ $RC -eq 1 ]]'
printf 'name: CI\njobs:\n  check:\n    steps:\n      - env:\n          SC_VERSION: 9.9.9\n' \
  > "$FR/.github/workflows/ci.yml"
printf '9.9.9\n' > "$STATE/SC_VER"
run "$FX"
check 2e  "pin without leading v still normalizes to a match" \
  '[[ $RC -eq 0 ]] && grep -q "local 9.9.9 == CI pin 9.9.9" <<<"$OUT"'

# ── 3. Argument handling ───────────────────────────────────────────────────
run "$FX" --help
check 3a  "--help exits 0, mentions make check and --strict" \
  '[[ $RC -eq 0 ]] && grep -q "make check" <<<"$OUT" && grep -q -- "--strict" <<<"$OUT"'
run "$FX" --bogus
check 3b  "unknown flag rejected non-zero" '[[ $RC -ne 0 ]]'
run "$FX" --strict --extra
check 3c  "too many args rejected" '[[ $RC -ne 0 ]]'

# ── 4. Real-repo integration (read-only) ───────────────────────────────────
REAL_PIN=$(sed -nE 's/^[[:space:]]*SC_VERSION:[[:space:]]*"?([^"[:space:]]+)"?/\1/p' \
  "$SCRIPT_DIR/.github/workflows/ci.yml" | head -n1)
PIN_BARE=${REAL_PIN#[vV]}
printf '%s\n' "$PIN_BARE" > "$STATE/SC_VER"
run "$SCRIPT"
check 4a  "real ci.yml pin parses and matches a pinned local shellcheck" \
  '[[ $RC -eq 0 ]] && grep -q "shellcheck parity: local $PIN_BARE == CI pin $REAL_PIN" <<<"$OUT"'
check 4b  "real run delegates to the real repo root" \
  '[[ $(tail -n1 "$STATE/MAKE_ARGS") == "-C '"$SCRIPT_DIR"' check" ]]'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
