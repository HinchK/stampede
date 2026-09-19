# ADR 0002: Exact-SHA Supervisor Protocol and Re-Verdict Deduplication

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: `arch`, `pm`, `looper`
- **Consulted**: [T-007a-fix](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-reverdict-dedupe-protocol.md), [T-007b](file:///Users/hinchk/Fun/loop-bot-herd-agy/maps/tickets/supervisor-genericization-and-profile-binding.md), [PM Herd Audit](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-pm-herd-audit.md)

---

## 1. Context and Problem Statement

The herd supervisor daemon (`loop-bot-herd.sh`) monitors worker agent terminal output, detects ticket completion events emitted by the implementation agent (`arch`), runs the repository's test suite as an automated gate, and logs verdicts to a session log (`session-verdicts.jsonl`).

In earlier versions, the supervisor's verdict harvesting logic had two critical defects:

1. **Substring Match Collision**: The deduplication logic relied on naive string grep (`grep -q "ARCH DONE #$ticket"`). Under this check, a verdict for ticket `#23` matched a log line for ticket `#230`, causing prefix-numbered tickets to be silently dropped without being tested.
2. **Permanent Lockout on RED Verdicts**: The deduplication check skipped any ticket number already recorded in `session-verdicts.jsonl`, *even when the previous verdict was `RED` (test failure)*. When `arch` received feedback that tests failed, fixed the bug, and emitted a new completion signal, the supervisor silently skipped it because the ticket was already present in the log. This broke the "fix and re-verdict" autonomous feedback loop, stranding tickets in failure states.

In addition, verdict lines lacked an explicit code-state identifier, leaving ambiguous whether an agent had made a new commit or was simply repeating an old message.

---

## 2. Decision Drivers

- **Support Autonomous Self-Healing**: When an implementation agent fails the test suite gate (`RED`), it must be able to iterate, commit fixes, and trigger an automated re-test.
- **Idempotency & Re-test Avoidance**: Avoid wasteful re-runs of heavy test suites if the codebase has not changed (`sha` is identical).
- **Exact Numeric Matching**: Eliminate string prefix collisions between ticket identifiers (e.g. `#1` vs `#10`, `#23` vs `#230`).
- **Structured Observability**: Verdicts must be recorded as well-formed JSONL with full attribution (`ticket`, `sha`, `seat`, `suite`, timestamp).

---

## 3. Considered Options

- **Option A (Simple In-Memory State)**: Keep an in-memory set of passed tickets in the bash supervisor loop. (Fragile across restarts and difficult to inspect).
- **Option B (Status Flag Overwrite in JSONL)**: Overwrite previous log entries when a ticket passes. (Destroys audit trail of test failures and regression history).
- **Option C (Exact `(ticket, sha)` Deduplication via `jq`)**: Upgrade the communication protocol to `ARCH DONE #<ticket> <sha>`, record immutable JSONL history, and use `jq` to differentiate between permanently retired tickets, redundant shas, and new commit states.

---

## 4. Decision

We adopted **Option C**. We established the **Exact-SHA Completion Protocol** across the architecture:

### A. Worker Completion Protocol (`ARCH DONE #<ticket> <sha>`)
Implementation agents (`arch`) are instructed via standing briefs ([`briefs/arch.in.md`](file:///Users/hinchk/Fun/loop-bot-herd-agy/briefs/arch.in.md) and [`briefs/arch.md`](file:///Users/hinchk/Fun/loop-bot-herd-agy/briefs/arch.md)) to emit completion lines in the explicit format:
```
ARCH DONE #<ticket> <sha>
```
Example: `ARCH DONE #42 7a8b9c0`

If the worker omits the SHA (e.g. `ARCH DONE #42`), the supervisor's parser automatically falls back to reading the short commit SHA directly from the repository's git HEAD:
```bash
sha=$(sed -nE 's/.*ARCH DONE #[0-9]+[[:space:]]+([0-9a-fA-F]{7,40}).*/\1/p' <<<"$verdict_line" | tail -n1)
[[ -n "$sha" ]] || sha=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
```

### B. Structured Verdict Logging
Every verdict is appended to `${TARGET_DIR}/.herdr-swarm/session-verdicts.jsonl` with an explicit schema:
```json
{
  "ts": 1726725000,
  "ticket": 42,
  "sha": "7a8b9c0",
  "seat": "arch-kultivait",
  "suite": "green",
  "verdict": "ARCH DONE #42 7a8b9c0"
}
```
Possible `suite` values are `"green"` (tests passed), `"RED"` (tests failed), or `"skipped"` (no test runner available).

### C. Two-Tier Deduplication Engine with `jq`
In [`loop-bot-herd.sh`](file:///Users/hinchk/Fun/loop-bot-herd-agy/loop-bot-herd.sh), `harvest_verdicts` applies a two-tier evaluation using `jq`:

1. **Permanent Retirement (Green / Skipped)**:
   If a ticket has already achieved a `green` or `skipped` verdict, it is permanently retired. Any subsequent completion lines for that ticket are ignored:
   ```bash
   if jq -e -s --argjson t "$ticket" \
      'any(.[]; .ticket == $t and (.suite == "green" or .suite == "skipped"))' \
      "$SESSION_LOG" >/dev/null 2>&1; then
     continue
   fi
   ```
2. **Exact `(ticket, sha)` State Deduplication**:
   If the ticket failed previously (`RED`), it is allowed to re-run **if and only if** the commit SHA is different from previous attempts. If the exact code commit has already been tested, it is skipped:
   ```bash
   if jq -e -s --argjson t "$ticket" --arg s "$sha" \
      'any(.[]; .ticket == $t and .sha == $s)' \
      "$SESSION_LOG" >/dev/null 2>&1; then
     continue
   fi
   ```

When a new commit SHA is presented for a previously failed ticket, the supervisor runs the suite gate against the new commit, appending a new record with the new verdict.

---

## 5. Consequences

### Positive
- **Fix-and-Reverdict Self Healing**: Implementation agents can receive error logs from a RED suite gate, produce a fixing commit, and re-emit completion; the supervisor immediately gates the new commit without manual log tampering.
- **Zero Ticket ID Collisions**: Exact numeric comparisons in `jq` (`.ticket == $t`) prevent `#23` from matching `#230`.
- **Immutable Historical Record**: Full failure and retry trajectories are preserved in `.herdr-swarm/session-verdicts.jsonl` for auditability and developer feedback.
- **Resource Efficiency**: Identical SHAs are never repeatedly tested, conserving compute resources.

### Negative / Trade-offs
- **External Dependency**: Requires `jq` on PATH (enforced via preflight matrix in [ADR 0005](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/adr/0005-preflight-matrix-and-seat-verification.md)).
- **Prompt Adherence**: Worker models must reliably emit the commit SHA or commit changes to git before signalling completion.
