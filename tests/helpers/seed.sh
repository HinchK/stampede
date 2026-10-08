#!/usr/bin/env bash
# tests/helpers/seed.sh — seeded-regression pairs (SEEDED-1). Sourced by the
# suites (tests/test_*.sh), never executed directly — hence not a TESTS
# wildcard member; held to the same lint bar via the Makefile's helpers glob.
#
# Discipline (from the OpenRig comparison §7 #1, adopted via BORROW-1): a
# state-machine test only counts if it FAILS when the defect is planted —
# passes-healthy is necessary, never sufficient. with_seeded_defect plants a
# defect by sed-editing the function's own `declare -f` text (post-source
# function redefinition — the GATE-1 suite pattern), runs the assertion body
# under the defect, and asserts the body FAILS. The original function is
# restored afterwards even when the body misbehaves. A sed expr that changes
# nothing is a rotted seed: rc 2, loud, never a silent pass.
#
# Usage:
#   with_seeded_defect <fn-name> <sed-expr> <assertion-body>
#     rc 0 — the body failed under the seed (teeth proven)
#     rc 1 — the body passed despite the defect (no teeth — the pair is bad)
#     rc 2 — setup error: unknown function or sed matched nothing
# The assertion body MUST also be shown passing on healthy code beside the
# seeded run — the pair is green-without-seed AND red-with-seed. Keep bodies
# self-contained: they run via eval with output discarded, and their side
# effects (verdict rows, ref moves) land in the suite's scratch fixtures.

with_seeded_defect() { # FN SED-EXPR ASSERTION-BODY
  local fn="$1" sedx="$2" body="$3"
  local orig seeded
  orig=$(declare -f "$fn" 2>/dev/null) || return 2
  seeded=$(printf '%s\n' "$orig" | sed "$sedx")
  if [[ "$seeded" == "$orig" ]]; then
    printf 'seeded-defect: sed matched nothing in %s — seed rotted?\n' "$fn" >&2
    return 2
  fi
  eval "$seeded" || true
  local rc=0
  if eval "$body" >/dev/null 2>&1; then
    rc=1
  fi
  eval "$orig" || true
  return "$rc"
}
