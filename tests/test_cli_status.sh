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

# STATUS-INDET-1 hermeticity: `stampede status --rich` derives seat presence
# via `herdr pane list` at read time. This suite must never query the host's
# real herdr — stub it for every invocation (empty pane table by default;
# the presence section below re-scripts the stub per scenario).
mkdir -p "$SCRATCH/herd-bin"
cat > "$SCRATCH/herd-bin/herdr" <<'EOF'
#!/bin/sh
printf '{"result":{"panes":[]}}\n'
EOF
chmod +x "$SCRATCH/herd-bin/herdr"
export PATH="$SCRATCH/herd-bin:$PATH"
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

# ── ROUTE-4: Seat Activity panel ──────────────────────────────────────────
# Second scratch repo, this one a real git repo: seats.json roster, trace
# events at controlled ages, commits with controlled dates and the two
# attribution conventions (integrate records + Co-Authored-By trailers).
echo "==> seat activity panel (ROUTE-4)"

NOW=$(date +%s)
ISO() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
D3=$(( NOW - 3 * 86400 ))
D10=$(( NOW - 10 * 86400 ))

R4="$SCRATCH/r4"
mkdir -p "$R4/.herdr-swarm/traces"
git -C "$R4" init -q
git -C "$R4" config user.email t@t && git -C "$R4" config user.name t
c() { # EPOCH MESSAGE [BODY] → commit, echo sha (subject first, body second)
  local ep="$1" msg="$2" body="${3:-}"
  GIT_AUTHOR_DATE="$(ISO "$ep")" GIT_COMMITTER_DATE="$(ISO "$ep")" \
    git -C "$R4" commit -q --allow-empty -m "$msg" ${body:+-m "$body"}
  git -C "$R4" rev-parse HEAD
}
# Chronological creation order: git log --since prunes heuristically on
# non-monotonic histories, so the fixture keeps commit dates non-decreasing
# down the chain (the shape every real repo has).
c "$D10" "chore: ancient" >/dev/null                       # outside 7d window
c "$D3"  "feat: work three (#T3)" >/dev/null               # in 7d, not in 1d → other
W1=$(c "$NOW" "fix: work one (#T1)")                       # → s1 via integrate ref
c "$NOW" "feat: work two (#T2)" "Co-Authored-By: s2-r4 <s2@seats>" >/dev/null  # → s2 via trailer
c "$NOW" "integrate #T1 (s1-r4 @ ${W1:0:7})" >/dev/null    # arbiter record → other
c "$NOW" "docs: bookkeeping" >/dev/null                    # → other

cat > "$R4/.herdr-swarm/seats.json" <<'EOF'
{"workspace_id": "w9", "seats": [
  {"name": "s1-r4", "kind": "opencode", "pane": "w9:p1"},
  {"name": "s2-r4", "kind": "agy", "pane": "w9:p2"}
]}
EOF
cat > "$R4/.herdr-swarm/traces/swarm-r4.jsonl" <<EOF
{"timestamp": $NOW, "iso": "x", "session_id": "s", "event_type": "lease.acquired", "agent": "s1-r4", "ticket_num": "T1", "payload": {}}
{"timestamp": $D3, "iso": "x", "session_id": "s", "event_type": "lease.acquired", "agent": "s2-r4", "ticket_num": "T2", "payload": {}}
{"timestamp": $D10, "iso": "x", "session_id": "s", "event_type": "lease.acquired", "agent": "s1-r4", "ticket_num": "T0", "payload": {}}
EOF
# one verdict record keeps the dashboard out of its empty state
printf '%s\n' '{"ts": 1, "ticket": "T1", "sha": "a1", "seat": "s1-r4", "suite": "green", "exit_code": 0}' \
  > "$R4/.herdr-swarm/session-verdicts.jsonl"

rc=0; a4=$("$S" status --rich --json "$R4" 2>/dev/null) || rc=$?
[[ "$rc" == 0 ]] && ok "r4: --json exits 0 on a git-backed target" || bad "r4 rc=$rc"
J '.activity.window_days == 7' <<<"$a4" \
  && ok "r4: default window 7d" || bad "r4 window: $(jq -c .activity.window_days <<<"$a4")"
J '[.activity.seats[] | select(.seat == "s1-r4") | .dispatches == 1 and .commits == 1] | length == 1 and all' <<<"$a4" \
  && ok "r4: s1 dispatches 1 (10d-old excluded) · commits 1 (integrate record attributes gated sha)" \
  || bad "r4 s1: $(jq -c '.activity.seats[] | select(.seat=="s1-r4")' <<<"$a4")"
J '[.activity.seats[] | select(.seat == "s2-r4") | .dispatches == 1 and .commits == 1] | length == 1 and all' <<<"$a4" \
  && ok "r4: s2 dispatches 1 · commits 1 (Co-Authored-By trailer)" \
  || bad "r4 s2: $(jq -c '.activity.seats[] | select(.seat=="s2-r4")' <<<"$a4")"
J '.activity.total_commits == 5 and .activity.other_commits == 3' <<<"$a4" \
  && ok "r4: total 5 in-window (ancient excluded) · other 3 (T3, integrate record, bookkeeping)" \
  || bad "r4 totals: $(jq -c '{t:.activity.total_commits,o:.activity.other_commits}' <<<"$a4")"
J '([.activity.gaps[] | select(test("auto-queue"))] | length) == 1' <<<"$a4" \
  && ok "r4: telemetry emission gap recorded, schema not widened" || bad "r4 gaps: $(jq -c .activity.gaps <<<"$a4")"

# --window 1: 3d-old dispatch and 3d-old commit fall out; ancient already out
rc=0; a1=$("$S" status --rich --json --window 1 "$R4" 2>/dev/null) || rc=$?
[[ "$rc" == 0 ]] && ok "r4: --window 1 accepted" || bad "r4 --window rc=$rc"
J '.activity.window_days == 1 and .activity.total_commits == 4
    and ([.activity.seats[] | select(.seat == "s2-r4") | .dispatches] | first) == null' <<<"$a1" \
  && ok "r4: window 1 — s2 dispatch n/a (3d-old excluded), T3 commit excluded (4 left)" \
  || bad "r4 w1: $(jq -c '{w:.activity.window_days,t:.activity.total_commits,s2:[.activity.seats[]|select(.seat=="s2-r4")|.dispatches]}' <<<"$a1")"
rc=0; "$S" status --rich --window abc "$R4" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] && ok "r4: --window abc rejected" || bad "r4: --window abc rc=$rc"

# traces absent → dispatches n/a (never fabricated zeros); commits unaffected
mv "$R4/.herdr-swarm/traces" "$SCRATCH/traces-parked"
rc=0; an=$("$S" status --rich --json "$R4" 2>/dev/null) || rc=$?
J '.activity.seats != [] and ([.activity.seats[] | select(.dispatches != null)] | length) == 0
    and .activity.total_commits == 5' <<<"$an" \
  && ok "r4: traces absent → every dispatches null, commits still real" \
  || bad "r4 n/a: $(jq -c '[.activity.seats[]|{s:.seat,d:.dispatches}]' <<<"$an")"
rc=0; ah=$("$S" status --rich "$R4" 2>/dev/null) || rc=$?
printf '%s' "$ah" | grep -q 'n/a' \
  && ok "r4: human table renders n/a for absent dispatch source" || bad "r4 human n/a missing"
mv "$SCRATCH/traces-parked" "$R4/.herdr-swarm/traces"

# non-git target (the original REPO fixture) → commits n/a, not zero
rc=0; ag=$("$S" status --rich --json 2>/dev/null) || rc=$?
J '.activity.total_commits == null and .activity.other_commits == null' <<<"$ag" \
  && ok "r4: non-git target → commits null (absence ≠ zero)" \
  || bad "r4 non-git: $(jq -c '{t:.activity.total_commits,o:.activity.other_commits}' <<<"$ag")"

# read-only: git side untouched (tracked files; the never-committed
# .herdr-swarm/ is legitimately untracked here), swarm state byte-identical
cp "$R4/.herdr-swarm/seats.json" "$SCRATCH/seats.before"
"$S" status --rich "$R4" >/dev/null 2>&1
"$S" status --rich --json --window 3 "$R4" >/dev/null 2>&1
git -C "$R4" diff --quiet && git -C "$R4" diff --cached --quiet \
  && cmp -s "$SCRATCH/seats.before" "$R4/.herdr-swarm/seats.json" \
  && ok "r4: read-only — no tracked-file drift, no swarm-state writes" || bad "r4: writes detected"

# ── STATUS-INDET-1: seat presence INDETERMINATE floor ──────────────────────
# Presence is derived at read time: seats.json (the ledger) supplies pane id
# + expected dir (worktree for isolated seats, repo root otherwise); the
# stubbed `herdr pane list` supplies the live pane table. Only positive
# confirmation renders present; everything else renders INDETERMINATE with
# a basis — never a confident claim from the recorded label.
echo "==> seat presence (STATUS-INDET-1)"
PH="$SCRATCH/herd-bin/herdr"
R4P=$(cd "$R4" && pwd -P)
# isolated seat: expected dir is its WORKTREE, not the repo root
mkdir -p "$R4/.herdr-swarm/worktrees/s3-r4"
cat > "$R4/.herdr-swarm/seats.json" <<EOF
{"workspace_id": "w9", "seats": [
  {"name": "s1-r4", "kind": "opencode", "pane": "w9:p1"},
  {"name": "s2-r4", "kind": "agy", "pane": "w9:p2"},
  {"name": "s3-r4", "kind": "opencode", "pane": "w9:p9", "worktree_dir": "$R4/.herdr-swarm/worktrees/s3-r4", "isolated": true}
]}
EOF

# (1) healthy: live panes, cwd exactly the expected dirs → present
cat > "$PH" <<EOF
#!/bin/sh
printf '{"result":{"panes":[{"pane_id":"w9:p1","cwd":"$R4P"},{"pane_id":"w9:p2","cwd":"$R4P"},{"pane_id":"w9:p9","cwd":"$R4P/.herdr-swarm/worktrees/s3-r4"}]}}\n'
EOF
rc=0; pj=$("$S" status --rich --json "$R4" 2>/dev/null) || rc=$?
[[ "$rc" == 0 ]] && ok "presence: healthy query exits 0" || bad "presence rc=$rc"
J '.presence.status == "ok" and .presence.basis == null and .presence.source != null
    and ([.presence.seats[] | select(.seat == "s1-r4") | .presence] | first) == "present"
    and ([.presence.seats[] | select(.seat == "s2-r4") | .presence] | first) == "present"
    and ([.presence.seats[] | select(.seat == "s3-r4") | .presence] | first) == "present"' <<<"$pj" \
  && ok "presence: anchor seats present (root cwd) + isolated seat present (worktree cwd)" \
  || bad "presence healthy: $(jq -c .presence <<<"$pj")"
rc=0; phout=$("$S" status --rich "$R4" 2>/dev/null) || rc=$?
printf '%s' "$phout" | grep -Eq 'w9:p1 +present' \
  && ok "presence: human row renders present" || bad "human present row missing"

# (2) cwd mismatch: pane alive but in the wrong dir (root instead of ITS worktree)
cat > "$PH" <<EOF
#!/bin/sh
printf '{"result":{"panes":[{"pane_id":"w9:p1","cwd":"/definitely/elsewhere"},{"pane_id":"w9:p2","cwd":"$R4P"},{"pane_id":"w9:p9","cwd":"$R4P"}]}}\n'
EOF
rc=0; pj=$("$S" status --rich --json "$R4" 2>/dev/null) || rc=$?
J '[.presence.seats[] | select(.seat == "s1-r4") | .presence] | first == "INDETERMINATE"' <<<"$pj" \
  && ok "presence: cwd mismatch renders INDETERMINATE, not present" \
  || bad "presence mismatch: $(jq -c '.presence.seats[] | select(.seat=="s1-r4")' <<<"$pj")"
J "[.presence.seats[] | select(.seat == \"s1-r4\") | .basis] | first == \"cwd mismatch: pane in /definitely/elsewhere, seat expects $R4P\"" <<<"$pj" \
  && ok "presence: mismatch basis names pane cwd and expected dir" \
  || bad "mismatch basis: $(jq -c '.presence.seats[] | select(.seat=="s1-r4") | .basis' <<<"$pj")"
J '[.presence.seats[] | select(.seat == "s3-r4") | .basis] | first | startswith("cwd mismatch") and contains("seat expects")' <<<"$pj" \
  && ok "presence: pane in repo ROOT still mismatches an isolated seat (expects worktree)" \
  || bad "s3 basis: $(jq -c '.presence.seats[] | select(.seat=="s3-r4") | .basis' <<<"$pj")"
rc=0; phout=$("$S" status --rich "$R4" 2>/dev/null) || rc=$?
printf '%s' "$phout" | grep -q 'INDETERMINATE (basis: cwd mismatch: pane in /definitely/elsewhere' \
  && ok "presence: human row renders the INDETERMINATE basis" || bad "human mismatch row missing"

# (3) dead pane: pane id absent from the live table
cat > "$PH" <<EOF
#!/bin/sh
printf '{"result":{"panes":[{"pane_id":"w9:p1","cwd":"$R4P"},{"pane_id":"w9:p9","cwd":"$R4P/.herdr-swarm/worktrees/s3-r4"}]}}\n'
EOF
rc=0; pj=$("$S" status --rich --json "$R4" 2>/dev/null) || rc=$?
J '[.presence.seats[] | select(.seat == "s2-r4") | .basis] | first == "dead pane: w9:p2 not in pane list"' <<<"$pj" \
  && ok "presence: dead pane basis names the missing pane" \
  || bad "dead pane basis: $(jq -c '.presence.seats[] | select(.seat=="s2-r4") | .basis' <<<"$pj")"

# (4) pane query failure: herdr present but the query itself fails
printf '#!/bin/sh\nexit 1\n' > "$PH"
rc=0; pj=$("$S" status --rich --json "$R4" 2>/dev/null) || rc=$?
J '.presence.status == "ok" and ([.presence.seats[] | select(.presence != "INDETERMINATE")] | length) == 0
    and ([.presence.seats[] | .basis] | all(. == "pane query failed: herdr pane list exited rc=1"))' <<<"$pj" \
  && ok "presence: failed pane query renders every seat INDETERMINATE (rc basis)" \
  || bad "query-failure rows: $(jq -c '.presence.seats[] | {s:.seat,b:.basis}' <<<"$pj")"

# (5) herdr not on PATH at all — probed in-process with a minimal bin that
# cannot contain herdr regardless of what the host has installed (removing
# the stub would expose the developer machine's real herdr: TEST-PATH-1's
# defect class, here in the test itself).
mkdir -p "$SCRATCH/presence-bin"
ln -sf "$(command -v jq)" "$SCRATCH/presence-bin/jq"
ln -sf "$(command -v cat)" "$SCRATCH/presence-bin/cat"
rc=0; out5=$(PATH="$SCRATCH/presence-bin" "$(command -v bash)" -c "
  source '$REPO_ROOT/lib/cli/stampede-status.sh'
  _status_presence_json '$R4/.herdr-swarm' '$R4'
" 2>/dev/null) || rc=$?
[[ "$rc" == 0 ]] \
  && J '.status == "ok" and ([.seats[] | .basis] | all(. == "pane query failed: herdr not on PATH"))' <<<"$out5" \
  && ok "presence: absent herdr renders INDETERMINATE (never confidently absent)" \
  || bad "no-herdr rows: $(jq -c '.seats[] | .basis' <<<"$out5")"
cat > "$PH" <<'EOF'
#!/bin/sh
printf '{"result":{"panes":[]}}\n'
EOF

# (6) missing seats.json: panel-level INDETERMINATE, not an empty panel
mv "$R4/.herdr-swarm/seats.json" "$SCRATCH/seats.parked"
rc=0; pj=$("$S" status --rich --json "$R4" 2>/dev/null) || rc=$?
J '.presence.status == "indeterminate" and .presence.basis == "seats.json unreadable: missing" and .presence.seats == []' <<<"$pj" \
  && ok "presence: missing seats.json → INDETERMINATE (basis: seats.json unreadable: missing)" \
  || bad "missing ledger: $(jq -c '{s:.presence.status,b:.presence.basis}' <<<"$pj")"
rc=0; phout=$("$S" status --rich "$R4" 2>/dev/null) || rc=$?
printf '%s' "$phout" | grep -q 'seats: INDETERMINATE (basis: seats.json unreadable: missing)' \
  && ok "presence: human panel renders the seats.json INDETERMINATE line" || bad "human missing-ledger line"

# (7) corrupt seats.json: same floor, invalid-json basis
printf 'this is not json\n' > "$R4/.herdr-swarm/seats.json"
rc=0; pj=$("$S" status --rich --json "$R4" 2>/dev/null) || rc=$?
J '.presence.status == "indeterminate" and .presence.basis == "seats.json unreadable: invalid json"' <<<"$pj" \
  && ok "presence: corrupt seats.json → INDETERMINATE (basis: invalid json)" \
  || bad "corrupt ledger: $(jq -c '{s:.presence.status,b:.presence.basis}' <<<"$pj")"
rc=0; phout=$("$S" status --rich "$R4" 2>/dev/null) || rc=$?
printf '%s' "$phout" | grep -q 'seats: INDETERMINATE (basis: seats.json unreadable: invalid json)' \
  && ok "presence: human panel renders the invalid-json INDETERMINATE line" || bad "human corrupt-ledger line"
mv "$SCRATCH/seats.parked" "$R4/.herdr-swarm/seats.json"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
