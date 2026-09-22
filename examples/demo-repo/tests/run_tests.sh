#!/bin/bash
# tests/run_tests.sh — the demo repo's real test suite
#
# Real assertions with real failure modes. `make test` runs this; the
# supervisor's Suite Gate runs `make test` too — same command, same
# verdict, no shortcuts. Plant the README's sabotage bug and watch this
# go red.

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/calc.sh"

t() { # desc want got
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want $2, got $3)"; fi
}

t "add positives"      "7"  "$(calc_add 3 4)"
t "add with negative"  "1"  "$(calc_add 5 -4)"
t "subtract"           "2"  "$(calc_sub 5 3)"
t "multiply"           "15" "$(calc_mul 3 5)"
t "divide exact"       "4"  "$(calc_div 12 3)"
t "divide truncates"   "3"  "$(calc_div 10 3)"

# divide-by-zero must fail loudly, never print a guess
if calc_div 5 0 >/dev/null 2>&1; then
  bad "divide by zero must exit non-zero"
else
  ok "divide by zero fails closed"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
