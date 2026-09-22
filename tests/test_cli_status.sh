#!/bin/bash
# tests/test_cli_status.sh — `stampede status --rich` (PUB-11)
#
# Hermetic: seeds a scratch repo's .herdr-swarm/ with fixture traces,
# verdicts, and an arbiter queue, then drives the REAL bin/stampede (the
# --rich seam) and asserts the JSON/human shapes, the re-verdict ratio
# computed from (ticket) history, read-only behaviour (no .herdr-swarm/
# file mtimes change across runs), and the fresh-clone empty state.

set -u
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$1"; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d /tmp/stampede-status.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT
REPO="$SCRATCH/repo"
mkdir -p "$REPO/.herdr-swarm/traces"

if ! command -v jq >/dev/null 2>&1; then
  printf 'test_cli_status: SKIP — jq not on PATH (a stampede preflight dependency)\n'
  exit 0
fi

# ── fixtures ────────────────────────────────────────────────────────────────
# verdicts: T1 green; T2 green→RED→RED (two re-verdicts, latest red);
# T3 skipped. 5 records / 3 distinct tickets → ratio 0.4.
cat > "$REPO/.herdr-swarm/session-verdicts.jsonl" <<'EOF'
{"ts": 1, "ticket": "T1", "sha": "a1", "seat": "s1", "suite": "green", "exit_code": 0}
{"ts": 2, "ticket": "T2", "sha": "b1", "seat": "s1", "suite": "green", "exit_code": 0}
{"ts": 3, "ticket": "T2", "sha": "b2", "seat": "s2", "suite": "RED", "exit_code": 1}
{"ts": 4, "ticket": "T2", "sha": "b3", "seat": "s2", "suite": "RED", "exit_code": 1}
{"ts": 5, "ticket": "T3", "sha": "c1", "seat": "s3", "suite": "skipped"}
EOF

# traces: three timed gates (1000/3000/2000ms → avg 2000, max 3000) plus an
# untimed event; PUB-10 absence semantics — missing duration is never averaged.
cat > "$REPO/.herdr-swarm/traces/swarm-fixture-1.jsonl" <<'EOF'
{"timestamp": 1000000000, "iso": "2001-09-09T01:46:40Z", "session_id": "swarm-fixture-1", "event_type": "suite.verdict", "agent": "s1", "ticket_num": "T1", "payload": {"ticket": "T1", "sha": "a1", "suite": "green", "gate.duration_ms": 1000, "verdict.attempt": 1}}
{"timestamp": 1000000010, "iso": "2001-09-09T01:46:50Z", "session_id": "swarm-fixture-1", "event_type": "suite.verdict", "agent": "s2", "ticket_num": "T2", "payload": {"ticket": "T2", "sha": "b2", "suite": "red", "gate.duration_ms": 3000, "verdict.attempt": 2}}
{"timestamp": 1000000020, "iso": "2001-09-09T01:47:00Z", "session_id": "swarm-fixture-1", "event_type": "suite.verdict", "agent": "s3", "ticket_num": "T3", "payload": {"ticket": "T3", "sha": "c1", "suite": "green", "gate.duration_ms": 2000, "verdict.attempt": 1}}
{"timestamp": 1000000030, "iso": "2001-09-09T01:47:10Z", "session_id": "swarm-fixture-1", "event_type": "swarm.lifecycle", "agent": "looper", "ticket_num": null, "payload": {"action": "swarm_ready"}}
{"timestamp": 1000000040, "iso": "2001-09-09T01:47:20Z", "session_id": "swarm-fixture-1", "event_type": "review.dispatched", "agent": "reviewer", "ticket_num": "REV-A", "payload": {"ticket": "REV-A", "sha": "ra1", "round": 1}}
{"timestamp": 1000000050, "iso": "2001-09-09T01:47:30Z", "session_id": "swarm-fixture-1", "event_type": "review.verdict", "agent": "reviewer", "ticket_num": "REV-A", "payload": {"ticket": "REV-A", "sha": "ra1", "verdict": "BLOCK", "round": 1, "findings_count": 1}}
{"timestamp": 1000000060, "iso": "2001-09-09T01:47:40Z", "session_id": "swarm-fixture-1", "event_type": "review.critique", "agent": "looper", "ticket_num": "REV-A", "payload": {"ticket": "REV-A", "sha": "ra1", "round": 2, "recipient": "s1"}}
{"timestamp": 1000000070, "iso": "2001-09-09T01:47:50Z", "session_id": "swarm-fixture-1", "event_type": "review.dispatched", "agent": "reviewer", "ticket_num": "REV-A", "payload": {"ticket": "REV-A", "sha": "ra2", "round": 2}}
{"timestamp": 1000000080, "iso": "2001-09-09T01:48:00Z", "session_id": "swarm-fixture-1", "event_type": "review.verdict", "agent": "reviewer", "ticket_num": "REV-A", "payload": {"ticket": "REV-A", "sha": "ra2", "verdict": "PASS", "round": 2, "findings_count": 0}}
{"timestamp": 1000000090, "iso": "2001-09-09T01:48:10Z", "session_id": "swarm-fixture-1", "event_type": "review.dispatched", "agent": "reviewer", "ticket_num": "REV-B", "payload": {"ticket": "REV-B", "sha": "rb1", "round": 1}}
{"timestamp": 1000000100, "iso": "2001-09-09T01:48:20Z", "session_id": "swarm-fixture-1", "event_type": "review.verdict", "agent": "reviewer", "ticket_num": "REV-B", "payload": {"ticket": "REV-B", "sha": "rb1", "verdict": "BLOCK", "round": 1, "findings_count": 2}}
EOF

# arbiter queue: 5 records across the status vocabulary.
cat > "$REPO/.herdr-swarm/integration.jsonl" <<'EOF'
{"ts": 1, "ticket": "T1", "seat": "s1", "sha": "a1", "status": "integrated", "merge_sha": "m1"}
{"ts": 2, "ticket": "T2", "seat": "s2", "sha": "b3", "status": "queued"}
{"ts": 3, "ticket": "T9", "seat": "s3", "sha": "z9", "status": "queued"}
{"ts": 4, "ticket": "T1", "seat": "s1", "sha": "a1", "status": "promoted"}
{"ts": 5, "ticket": "T5", "seat": "s1", "sha": "e1", "status": "conflict"}
EOF

# provider kinds join: s1→claude, s2→opencode chain, s3→agy.
cat > "$SCRATCH/config.toml" <<'EOF'
[seats.s1]
name = "s1"
default_kind = "claude"
[seats.s2]
name = "s2"
kinds = ["opencode", "claude"]
[seats.s3]
name = "s3"
default_kind = "agy"
EOF

# Resolve the interpreter up front (absolute PYTHON_BIN survives the test's
# normal PATH; the CLI re-resolves internally from the preset).
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/pyenv.sh"
if ! resolve_python >/dev/null 2>&1; then
  printf 'test_cli_status: SKIP — no tomllib-capable interpreter on PATH\n'
  exit 0
fi

export REPO_DIR="$REPO"
export STAMPEDE_CONFIG="$SCRATCH/config.toml"
S="$REPO_ROOT/bin/stampede"
J() { jq -e "$1"; }  # readability for assertion pipelines
# NOTE: sourcing lib/pyenv.sh above arms `set -e` in this shell (the lib
# sets it itself). Every command expected to fail is captured errexit-safe
# (`|| rc=$?`) so one red exit cannot kill the suite silently.

echo "==> stampede status --rich (PUB-11)"

# ── JSON shape: tickets by verdict, latest record wins ─────────────────────
rc=0; out=$("$S" status --rich --json 2>/dev/null) || rc=$?
[[ "$rc" == 0 ]] && ok "--json exits 0" || bad "rc=$rc"
J '.tickets.green == 1 and .tickets.red == 1 and .tickets.skipped == 1 and .tickets.other == 0 and .tickets.total == 3' <<<"$out" \
  && ok "tickets by verdict: latest record per ticket wins (T2 red)" || bad "tickets: $(jq -c .tickets <<<"$out")"

# verification-step contract, verbatim
printf '%s' "$out" | jq -e '.tickets' >/dev/null && ok "verification contract: | jq -e '.tickets' passes" || bad ".tickets falsy"

# ── re-verdict ratio from history, not memory ──────────────────────────────
J '.reverdicts.records == 5 and .reverdicts.distinct_tickets == 3 and .reverdicts.extra == 2 and .reverdicts.ratio == 0.4' <<<"$out" \
  && ok "re-verdict ratio 2 extra / 5 records = 0.4 from JSONL history" || bad "reverdicts: $(jq -c .reverdicts <<<"$out")"

# ── gates: counts from verdicts, durations from traces only ────────────────
J '.gates.runs == 5 and .gates.timed_runs == 3 and .gates.avg_ms == 2000 and .gates.max_ms == 3000' <<<"$out" \
  && ok "gate runs 5; durations averaged only where present (avg 2000, max 3000)" || bad "gates: $(jq -c .gates <<<"$out")"

# ── integrations from the arbiter queue ────────────────────────────────────
J '.integration.enqueued == 5 and .integration.queued == 2 and .integration.integrated == 1 and .integration.promoted == 1 and .integration.conflict == 1 and .integration.integration_red == 0' <<<"$out" \
  && ok "integration counts match the queue" || bad "integration: $(jq -c .integration <<<"$out")"

# ── review loop rollup (REV-4), every count from named trace events ───────
printf '%s' "$out" | jq -e '.reviews' >/dev/null && ok "verification contract: | jq -e '.reviews' passes" || bad ".reviews falsy"
J '.reviews.total == 3 and .reviews.passes == 1 and .reviews.blocks == 2 and .reviews.rerounds == 1 and .reviews.findings_total == 3' <<<"$out" \
  && ok "reviews: dispatched 3, pass 1, block 2, re-rounds 1, findings 3" || bad "reviews: $(jq -c .reviews <<<"$out")"
J '[.reviews.tickets[] | select(.ticket == "REV-A") | .rounds == 2 and .verdicts == 2 and .critiques == 1] | length == 1' <<<"$out" \
  && ok "per-ticket review detail: REV-A 2 rounds, 2 verdicts, 1 critique" || bad "REV-A: $(jq -c '.reviews.tickets[] | select(.ticket == "REV-A")' <<<"$out")"

# ── per-seat and per-provider activity ─────────────────────────────────────
J '[.seats[] | select(.seat == "s2") | .gates == 2 and .red == 2 and .kinds == "opencode,claude"] | length == 1' <<<"$out" \
  && ok "seat row s2 carries gates/red and its kind chain from config" || bad "s2 row: $(jq -c '.seats[] | select(.seat == "s2")' <<<"$out")"
J '([.providers[] | select(.kind == "claude") | .gates] | add) == 2 and ([.providers[] | select(.kind == "opencode") | .gates] | add) == 2 and ([.providers[] | select(.kind == "agy") | .gates] | add) == 1' <<<"$out" \
  && ok "provider rollup: primary-kind attribution (claude 2, opencode 2, agy 1)" || bad "providers: $(jq -c .providers <<<"$out")"

# ── sources are named ──────────────────────────────────────────────────────
J '.sources.traces != null and (.sources.verdicts | endswith("session-verdicts.jsonl")) and (.sources.arbiter_queue | endswith("integration.jsonl")) and .sources.config != null' <<<"$out" \
  && ok "--json names its sources" || bad "sources: $(jq -c .sources <<<"$out")"
J '.sessions == ["swarm-fixture-1"] and .read_only == true and .empty == false' <<<"$out" \
  && ok "session list and read-only flag present" || bad "meta: $(jq -c '{sessions, read_only, empty}' <<<"$out")"

# ── human table: deterministic strings, no ANSI when piped ──────────────────
rc=0; human=$("$S" status --rich 2>/dev/null) || rc=$?
[[ "$rc" == 0 ]] && ok "human mode exits 0" || bad "human rc=$rc"
printf '%s' "$human" | grep -q 'green 1 · red 1 · skipped 1 · other 0  (3 with a verdict)' \
  && ok "human ticket line rendered" || bad "human tickets line missing"
printf '%s' "$human" | grep -q '2 extra / 5 records (3 distinct tickets) = 40.0%' \
  && ok "human re-verdict line rendered" || bad "human re-verdict line: $human"
printf '%s' "$human" | grep -q 'enqueued 5 · queued 2' \
  && ok "human arbiter line rendered" || bad "human arbiter line missing"
printf '%s' "$human" | grep -q 'dispatched 3 · pass 1 · block 2 · re-rounds 1' \
  && ok "human review line rendered" || bad "human review line missing"
printf '%s' "$human" | grep -q 'REV-A .*rounds 2 · verdicts 2 · critiques 1' \
  && ok "human per-ticket review detail rendered" || bad "human REV-A line missing"
if printf '%s' "$human" | grep -q $'\033'; then
  bad "no ANSI escapes when piped"
else
  ok "no ANSI escapes when piped (deterministic)"
fi

# ── torn-line resilience: garbage records are dropped, not fatal ───────────
printf 'this-is-not-json\n' >> "$REPO/.herdr-swarm/session-verdicts.jsonl"
rc=0; out2=$("$S" status --rich --json 2>/dev/null) || rc=$?
J '.tickets.total == 3 and .reverdicts.records == 5' <<<"$out2" \
  && ok "torn/garbage JSONL lines dropped without failing the aggregate" || bad "resilience: $(jq -c '{t:.tickets.total,r:.reverdicts.records}' <<<"$out2")"

# ── read-only: no .herdr-swarm/ file mtimes change across runs ─────────────
rm -f "$REPO/.herdr-swarm/session-verdicts.jsonl"
printf '%s\n' '{"ts": 9, "ticket": "T1", "sha": "a1", "seat": "s1", "suite": "green"}' > "$REPO/.herdr-swarm/session-verdicts.jsonl"
touch "$SCRATCH/marker"
"$S" status --rich >/dev/null 2>&1
"$S" status --rich --json >/dev/null 2>&1
newer=$(find "$REPO/.herdr-swarm" -type f -newer "$SCRATCH/marker" 2>/dev/null)
[[ -z "$newer" ]] && ok "read-only: no .herdr-swarm/ file created or touched across runs" \
  || bad "writes detected: $newer"

# ── fresh clone: friendly empty state, exit 0, valid JSON ──────────────────
EMPTY="$SCRATCH/fresh"
mkdir -p "$EMPTY"
rc=0; eh=$(REPO_DIR="$EMPTY" "$S" status --rich 2>/dev/null) || rc=$?
[[ "$rc" == 0 ]] && ok "empty state exits 0" || bad "empty rc=$rc"
printf '%s' "$eh" | grep -q "Nothing to report yet" \
  && ok "empty state is friendly" || bad "empty state message: $eh"
printf '%s' "$eh" | grep -q "docs/user-guide.md" \
  && ok "empty state points at the user guide" || bad "no guide pointer"
ej=$(REPO_DIR="$EMPTY" "$S" status --rich --json 2>/dev/null)
J '.empty == true and .tickets.total == 0 and .sources.traces == null and .sources.verdicts == null and .sources.arbiter_queue == null' <<<"$ej" \
  && ok "empty JSON: zeroed, sources null" || bad "empty json: $(jq -c '{empty, sources}' <<<"$ej")"
printf '%s' "$ej" | jq -e '.tickets' >/dev/null && ok "empty JSON still satisfies | jq -e '.tickets'" || bad "empty .tickets"

# ── routing seam: plain `status [dir]` still delegates to the launcher ─────
D="$SCRATCH/delegate"
mkdir -p "$D/bin" "$D/lib/cli"
cp "$REPO_ROOT/bin/stampede" "$D/bin/stampede"
cp "$REPO_ROOT/lib/cli/stampede-status.sh" "$D/lib/cli/"
mkdir -p "$D/lib"
cp "$REPO_ROOT/lib/pyenv.sh" "$REPO_ROOT/lib/providers.sh" "$D/lib/"
printf '#!/usr/bin/env bash\nprintf '"'"'LAUNCHER-ARGV:%%s\\n'"'"' "$*"\n' > "$D/herdr-loop-swarm.sh"
chmod +x "$D/bin/stampede" "$D/herdr-loop-swarm.sh"
dout=$("$D/bin/stampede" status mydir 2>&1)
[[ "$dout" == "LAUNCHER-ARGV:status mydir" ]] \
  && ok "plain 'status [dir]' still delegates verbatim (PUB-1 unchanged)" || bad "delegation: $dout"
rc=0; dout=$("$D/bin/stampede" status --rich --json 2>&1) || rc=$?
printf '%s' "$dout" | jq -e '.tickets' >/dev/null 2>&1 \
  && ok "seam routes --rich/--json to the module" || bad "seam routing (rc=$rc): $dout"
rm -rf "$D/lib/cli"
rc=0; dout=$(cd "$D" && ./bin/stampede status --rich 2>&1) || rc=$?
[[ "$dout" == "LAUNCHER-ARGV:status --rich" ]] \
  && ok "absent module falls back to launcher pass-through (graceful)" || bad "fallback: $dout"

# ── help and flag discipline ────────────────────────────────────────────────
rc=0; out=$("$S" status --help 2>&1) || rc=$?
[[ "$rc" == 0 && "$out" == *"Usage: stampede status --rich"* ]] && ok "--help rc=0" || bad "help rc=$rc"
rc=0; "$S" status --bogus >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 ]] && ok "unknown flag rc=1" || bad "unknown flag rc=$rc"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
