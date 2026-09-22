#!/bin/bash
# tests/test_telemetry.sh — envelope + round-trip (PUB-10)
#
# The envelope is a contract: string ticket ids survive verbatim (ARB-STR —
# the old CLI silently nulled anything non-numeric), measured fields pass
# through untouched, absent fields stay absent, and `stream --once`
# replays what `log` wrote.

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-telemetry.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

PY=python3
command -v "$PY" >/dev/null 2>&1 || { printf 'test_telemetry: SKIP — no python3\n'; exit 0; }
T="$REPO_ROOT/lib/telemetry.py"

echo "==> telemetry envelope + round-trip (PUB-10)"

# [1] string ticket id survives verbatim (the ARB-STR regression)
"$PY" "$T" log s1 suite.verdict arch DEMO-1 '{"suite":"green"}' --trace-dir "$SCRATCH"
line=$(tail -n1 "$SCRATCH/s1.jsonl")
[[ "$line" == *'"ticket_num": "DEMO-1"'* ]] && ok "string ticket id verbatim" || bad "ticket dropped: $line"

# [2] numeric-looking ticket id keeps textual form; "-" means none
"$PY" "$T" log s1 suite.verdict arch 23 '{"suite":"red"}' --trace-dir "$SCRATCH"
line=$(tail -n1 "$SCRATCH/s1.jsonl")
[[ "$line" == *'"ticket_num": "23"'* ]] && ok "numeric id stored as string" || bad "23: $line"
"$PY" "$T" log s1 swarm.lifecycle looper - '{"action":"swarm_ready"}' --trace-dir "$SCRATCH"
line=$(tail -n1 "$SCRATCH/s1.jsonl")
[[ "$line" == *'"ticket_num": null'* ]] && ok 'dash means null ticket' || bad "dash: $line"

# [3] measured fields pass through untouched; absent usage stays absent
"$PY" "$T" log s1 suite.verdict arch PUB-10 '{"suite":"green","gate.duration_ms":4200,"verdict.attempt":2,"usage":{"tokens_in":10,"cost":0.02}}' --trace-dir "$SCRATCH"
line=$(tail -n1 "$SCRATCH/s1.jsonl")
[[ "$line" == *'"gate.duration_ms": 4200'* && "$line" == *'"cost": 0.02'* ]] \
  && ok "measured fields verbatim" || bad "fields mangled: $line"
"$PY" "$T" log s1 quota.probe arch - '{"status":"unknown"}' --trace-dir "$SCRATCH"
line=$(tail -n1 "$SCRATCH/s1.jsonl")
[[ "$line" != *'"usage"'* ]] && ok "absent usage stays absent" || bad "usage invented: $line"

# [4] stream --once replays: ticket + summary visible in the badge line
out=$("$PY" "$T" stream s1 "$SCRATCH" --once | grep -c 'DEMO-1')
[[ "$out" -ge 1 ]] && ok "stream --once renders string ticket" || bad "ticket missing from stream"

# [5] payload with unicode survives the JSONL round-trip
"$PY" "$T" log s1 swarm.dispatch looper DEMO-2 '{"summary":"dispatch ✓"}' --trace-dir "$SCRATCH"
line=$(tail -n1 "$SCRATCH/s1.jsonl")
[[ "$line" == *'dispatch ✓'* ]] && ok "unicode summary verbatim" || bad "unicode: $line"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
