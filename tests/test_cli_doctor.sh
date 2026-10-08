#!/bin/bash
# tests/test_cli_doctor.sh — `stampede doctor` end-to-end (PUB-2)
#
# Hermetic: scratch config + scratch PATH stubbing herdr/gh/jq/timeout and
# the provider CLIs under test, inside a scratch git repo. Proves the seat
# table (OK / MISSING+remediation / SKIP for disabled seats / BAD-KIND for
# unregistered kinds), preflight integration, and the exit-code contract:
# enabled seats decide the exit; disabled seats never do.

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1 (rc=$3)"; else bad "$1 (want rc=$2, got rc=$3)"; fi; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-doctor.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/bin"
cd "$SCRATCH" && git init -q .

# ── PATH stubs: every preflight error-level probe goes green; provider
# presence is varied per case below.
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$SCRATCH/bin/$1"; chmod +x "$SCRATCH/bin/$1"; }
stub herdr   'exit 0'
stub gh      'exit 0'
stub timeout 'shift; exec "$@"'
stub claude  'echo "claude 1.2.3 (stub)"'
stub agy     'echo "agy 9.9 (stub)"'

# jq must be REAL: doctor's HERDR-3 lifecycle section parses herdr JSON
# with it (the presence-stub predates that). Same policy as
# tests/test_cli_status.sh — skip the suite when jq is unavailable.
if REAL_JQ=$(command -v jq); then
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$REAL_JQ" > "$SCRATCH/bin/jq"
  chmod +x "$SCRATCH/bin/jq"
else
  printf 'test_cli_doctor: SKIP — jq not on PATH (a stampede preflight dependency)\n'
  exit 0
fi

# Resolve the interpreter with the FULL path first, then narrow.
if ! PYTHON_OUT=$(cd "$REPO_ROOT" && bash lib/pyenv.sh 2>/dev/null); then
  printf 'test_cli_doctor: SKIP — no tomllib-capable interpreter on PATH\n'
  exit 0
fi
export PYTHON_BIN="$PYTHON_OUT"

# Minimal PATH: scratch stubs + system basics. Real provider CLIs on the
# dev machine must not make a MISSING-seat case silently pass.
PATH="$SCRATCH/bin:/usr/bin:/bin"
export PATH

cfg="$SCRATCH/swarm.config.toml"

echo "==> stampede doctor (PUB-2)"

# [1] one healthy enabled seat + one disabled → rc 0, OK and SKIP rows
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
[seats.pi]
name = "pi"
default_kind = "pi"
enabled = false
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "healthy enabled + disabled seat → rc 0" 0 "$rc"
printf '%s\n' "$out" | grep -Eq 'pm +claude +OK' && ok "enabled healthy seat row OK" || bad "pm row missing"
printf '%s\n' "$out" | grep -q 'pi *pi *SKIP' && ok "disabled seat row SKIP" || bad "pi row missing SKIP"
[[ "$out" == *"preflight:"* ]] && ok "preflight matrix included" || bad "no preflight output"

# [2] enabled seat with missing provider → rc 1 + remediation in the row
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
[seats.arch_1]
name = "arch-1"
default_kind = "opencode"
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "missing provider on enabled seat → rc 1" 1 "$rc"
printf '%s\n' "$out" | grep -Eq 'arch_1 +opencode +MISSING' \
  && printf '%s\n' "$out" | grep -q 'opencode.ai' \
  && ok "MISSING row carries install pointer" || bad "arch_1 row missing"

# [3] enabled seat with unregistered kind → rc 1, BAD-KIND
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
[seats.weird]
name = "weird"
default_kind = "brand-new-llm"
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "unregistered kind on enabled seat → rc 1" 1 "$rc"
[[ "$out" == *"BAD-KIND"* ]] && ok "BAD-KIND surfaced" || bad "no BAD-KIND: $out"

# [4] preflight failure also fails doctor: kill the gh stub's auth
stub gh 'exit 1'
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "preflight error (gh auth) → rc 1" 1 "$rc"
[[ "$out" == *"gh-auth"* ]] && ok "gh-auth failure surfaced" || bad "gh-auth: $out"

# [5] missing config → rc 1, no table
out=$(STAMPEDE_CONFIG="$SCRATCH/nope.toml" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "missing config → rc 1" 1 "$rc"
[[ "$out" == *"config not found"* ]] && ok "missing config message" || bad "cfg msg: $out"

# [6] provider chains (PUB-6): healthy fallback kind → rc 0 + FALLBACK row;
# dead whole chain → rc 1 + MISSING with the primary's remedy
stub gh 'exit 0'   # restore: case 4 sabotaged auth for its own assertion
cat > "$cfg" <<'EOF'
[seats.arch_1]
name = "arch-1"
kinds = ["opencode", "claude"]
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "chain with healthy fallback → rc 0" 0 "$rc"
printf '%s\n' "$out" | grep -Eq 'arch_1 +opencode,claude +FALLBACK' \
  && ok "FALLBACK row names primary and live kind" || bad "fallback row: $out"

# [7] HERDR-3: explain diagnostics — unsupported probe → note, exit intact
cat > "$SCRATCH/bin/herdr" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "agent" ] && [ "$2" = "explain" ]; then exit 2; fi
exit 0
EOF
chmod +x "$SCRATCH/bin/herdr"
cat > "$cfg" <<'EOF'
[seats.pm]
name = "pm"
default_kind = "claude"
EOF
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "explain probe unsupported → rc still 0" 0 "$rc"
[[ "$out" == *"explain unavailable"* ]] && ok "unsupported probe prints one note" || bad "note missing: $out"

# [8] HERDR-3: ambiguous seat (state unknown) → explain runs, matched rule
# printed; healthy seat in the same herd is NOT explained
cat > "$SCRATCH/bin/herdr" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "agent" ] && [ "$2" = "explain" ] && [ "$3" = "--help" ]; then exit 0; fi
if [ "$1" = "agent" ] && [ "$2" = "list" ]; then
  printf '%s\n' '{"result":{"agents":[
    {"name":"pm-demo","state":"unknown","agent":"claude","pane_id":"w1:p1"},
    {"name":"arch-1-demo","state":"idle","agent":"opencode","pane_id":"w1:p2"}]}}'
  exit 0
fi
if [ "$1" = "agent" ] && [ "$2" = "explain" ]; then
  echo "$3" >> "$DOCTOR_EXPLAIN_LOG"
  printf '%s\n' '{"state":"unknown","matched_rule":"screen.ambiguous_idle",
                  "evaluated_rules":[{"id":"a"},{"id":"b"}],
                  "fallback_reason":null,"screen_detection_skip_reason":null,
                  "warning":null}'
  exit 0
fi
exit 0
EOF
chmod +x "$SCRATCH/bin/herdr"
export DOCTOR_EXPLAIN_LOG="$SCRATCH/explain.log"; : > "$DOCTOR_EXPLAIN_LOG"
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "ambiguous seat present → rc still 0 (advisory)" 0 "$rc"
[[ "$out" == *"explain pm-demo"*"state=unknown"*"rule=screen.ambiguous_idle"* ]] \
  && ok "ambiguous seat explained with matched rule" || bad "explain line: $out"
grep -qx "pm-demo" "$DOCTOR_EXPLAIN_LOG" \
  && ok "explain ran for the ambiguous seat only" || bad "explain log: $(cat "$DOCTOR_EXPLAIN_LOG")"
if grep -q "arch-1-demo" "$DOCTOR_EXPLAIN_LOG"; then
  bad "healthy seat was explained (must be skipped)"
else
  ok "healthy seat skipped by explain"
fi

# [9] HERDR-3: healthy herd → explain skipped entirely
cat > "$SCRATCH/bin/herdr" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "agent" ] && [ "$2" = "explain" ] && [ "$3" = "--help" ]; then exit 0; fi
if [ "$1" = "agent" ] && [ "$2" = "list" ]; then
  printf '%s\n' '{"result":{"agents":[
    {"name":"pm-demo","state":"idle","agent":"claude","pane_id":"w1:p1"},
    {"name":"arch-1-demo","state":"working","agent":"opencode","pane_id":"w1:p2"}]}}'
  exit 0
fi
if [ "$1" = "agent" ] && [ "$2" = "explain" ]; then
  echo "$3" >> "$DOCTOR_EXPLAIN_LOG"; exit 0
fi
exit 0
EOF
chmod +x "$SCRATCH/bin/herdr"
: > "$DOCTOR_EXPLAIN_LOG"
out=$(STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "healthy herd → rc 0" 0 "$rc"
[[ "$out" == *"none ambiguous — explain skipped"* ]] \
  && ok "healthy herd reports skip line" || bad "skip line: $out"
[[ ! -s "$DOCTOR_EXPLAIN_LOG" ]] && ok "no explain calls on a healthy herd" || bad "explain ran: $(cat "$DOCTOR_EXPLAIN_LOG")"

# [10] HERDR-3: foreign agents never explained — seat identity is exact via
# the seat ledger when one exists (prefix heuristic is the fallback only)
mkdir -p "$SCRATCH/tgt/.herdr-swarm"
cat > "$SCRATCH/tgt/.herdr-swarm/seats.json" <<'EOF'
{"workspace_id": "w1", "seats": [
  {"name": "pm-demo", "kind": "claude", "pane": "w1:p1"},
  {"name": "arch-1-demo", "kind": "opencode", "pane": "w1:p2"}
]}
EOF
cat > "$SCRATCH/bin/herdr" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "agent" ] && [ "$2" = "explain" ] && [ "$3" = "--help" ]; then exit 0; fi
if [ "$1" = "agent" ] && [ "$2" = "list" ]; then
  printf '%s\n' '{"result":{"agents":[
    {"name":"pm-otherproject","state":"unknown","agent":"claude","pane_id":"w2:p1"},
    {"name":"pm-demo","state":"unknown","agent":"claude","pane_id":"w1:p1"}]}}'
  exit 0
fi
if [ "$1" = "agent" ] && [ "$2" = "explain" ]; then
  echo "$3" >> "$DOCTOR_EXPLAIN_LOG"
  printf '%s\n' '{"state":"unknown","matched_rule":"screen.ambiguous_idle",
                  "evaluated_rules":[],"fallback_reason":null,
                  "screen_detection_skip_reason":null,"warning":null}'
  exit 0
fi
exit 0
EOF
chmod +x "$SCRATCH/bin/herdr"
: > "$DOCTOR_EXPLAIN_LOG"
out=$(REPO_DIR="$SCRATCH/tgt" STAMPEDE_CONFIG="$cfg" "$REPO_ROOT/bin/stampede" doctor 2>&1); rc=$?
check "ledger-precise filter → rc 0" 0 "$rc"
grep -qx "pm-demo" "$DOCTOR_EXPLAIN_LOG" \
  && ok "ledger seat in unknown state explained" || bad "log: $(cat "$DOCTOR_EXPLAIN_LOG")"
if grep -q "pm-otherproject" "$DOCTOR_EXPLAIN_LOG"; then
  bad "foreign agent explained despite ledger"
else
  ok "foreign agent filtered out (ledger names are exact)"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
