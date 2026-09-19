# P2-3 Spec — Supervisor Worktree Suite Gating (`pm`)

**Date:** 2026-09-19 · **Against:** `main` @ `82ae09b` · **Target file:** `loop-bot-herd.sh` (`harvest_verdicts`, today `:125-195`)
**Depends on:** P2-1 `lib/worktree.sh` (landed, `99867cf`), P2-2 ledger v2 (spec `b01b81f`, not yet implemented)
**Evidence:** probes on git 2.55.0 in a scratch repo (worktree commits, provenance, drift, `-B` re-seat). Results are quoted inline.

## 0. Why this ticket matters

Once arch works in `.herdr-swarm/worktrees/arch-<slug>`, today's gate becomes a **structural false green**. It runs
`cd "$REPO_DIR" && $TEST_CMD` (`:162`), which tests the root checkout. The worker's changes aren't there. So every verdict gates
`main`'s code and passes. P2-3 must land **together with** P2-2's launcher change, never after it.

### Blocking prerequisite found while writing this spec (P2-1 defect)

`worktree_provision` runs `git worktree add -B "$branch" …` (`lib/worktree.sh:42`). **`-B` resets an existing branch to `base_ref`.**
Probe: `swarm/t4` with 20 unmerged commits → re-seat with `-B` → **0 unmerged commits**. The work survives only in the reflog, which expires.
This violates ADR 0006 "work is never lost" and P2-2 amendment A2. For this ticket it also means a verdict sha from before a
re-seat stops being on the seat branch (§3 would then correctly reject it, but the work is already gone).
**Fix before P2-3 merges:** use `-b` for new branches. For an existing branch, attach without reset, and only if not stale (P2-2 §4.2).

---

## 1. Ledger lookup — resolving a seat's gate directory

Resolution is **ledger-first, fail-closed for isolated seats**. The `// $REPO_DIR` fallback in the brief is correct for root and
legacy seats only. Applied to an isolated seat whose worktree is missing, it would test the root and green-light it, which is the
exact false green in §0. The fallback therefore depends on `isolated`:

```bash
# resolve_seat_gate SEAT  → sets GATE_DIR, GATE_BRANCH, GATE_ISOLATED; returns 1 = cannot gate (escalate)
resolve_seat_gate() {
  local seat="$1" ledger="${STATE_DIR}/seats.json" rec
  GATE_DIR="$REPO_DIR"; GATE_BRANCH=""; GATE_ISOLATED=false
  [[ -f "$ledger" ]] || return 0                                  # no ledger: legacy root gating
  rec=$(jq -c --arg s "$seat" '.seats[]? | select(.name == $s)' "$ledger" 2>/dev/null | head -n1)
  [[ -n "$rec" ]] || return 0                                     # seat not in ledger: root gating (v1 / root seat)
  GATE_ISOLATED=$(jq -r '.isolated // false' <<<"$rec")
  GATE_BRANCH=$(jq -r '.branch // empty' <<<"$rec")
  if [[ "$GATE_ISOLATED" == "true" ]]; then
    GATE_DIR=$(jq -r '.worktree_dir // empty' <<<"$rec")
    [[ -n "$GATE_DIR" && -d "$GATE_DIR" ]] || return 1            # isolated but gone → NEVER fall back to root
    [[ "$(git -C "$GATE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$GATE_BRANCH" ]] || return 1
  else
    GATE_DIR=$(jq -r --arg d "$REPO_DIR" '.worktree_dir // $d' <<<"$rec")
  fi
}
```

Rules:
- Matching is on the **exact namespaced seat name** (`arch-<slug>`), the same string `EXPECTED_SEATS` holds and the pane is read from.
- `resolve_seat_gate` returning 1 ⇒ record `suite: "unresolvable"` (§4), prompt looper "do NOT retire, human evaluation required",
  and **do not run the suite**.
- A v1 ledger (no `isolated`) resolves every seat to the root, which is today's behaviour. This makes P2-3 safe to merge before any seat is isolated.
- The ledger is **read on every harvest pass** (not cached), because P2-2 re-seats rewrite it.

---

## 2. Execution directory and the state being tested

Gating in the worktree is necessary but not sufficient. The worker keeps editing after it prints its verdict, so the tree
at gate time may not be the commit the verdict names. Probe: after a verdict, a further edit plus an untracked test file gave
`HEAD==sha: yes`, dirty: 2 paths. **`--untracked-files=no` reported only 1**, missing the untracked `*_test.py` that the runner would collect.

**Precondition (checked immediately before the run):**

```bash
[[ "$(git -C "$GATE_DIR" rev-parse HEAD)" == "$(git -C "$GATE_DIR" rev-parse "${sha}^{commit}")" ]]   # HEAD is the verdict sha
[[ -z "$(git -C "$GATE_DIR" status --porcelain)" ]]                                                   # clean INCLUDING untracked
```

If either fails ⇒ `suite: "stale"`. Do not run. Prompt the seat: "commit your changes or remove stray files (no `git stash`), then re-verdict
`ARCH DONE #n <new sha>`". A stale record doesn't retire the ticket or count as RED. The (ticket, sha) dedupe must allow
a later verdict at the same sha once the tree is clean. Implement this by excluding `stale`/`unresolvable` records from the sha-dedupe check.

**Run:**

```bash
( cd "$GATE_DIR" \
  && TMPDIR="${STATE_DIR}/gate-tmp/${seat}" \
     timeout "$SUITE_TIMEOUT_S" sh -c "$TEST_CMD" ) >"${STATE_DIR}/gate-logs/${seat}-${sha}.log" 2>&1
```

- `TMPDIR` per seat (advisory H5). Output is kept in a log file, not `/dev/null`, so a RED is diagnosable. The log path goes into the record.
- **Post-condition (TOCTOU):** re-check `HEAD == sha` and clean tree after the run. If the worker changed the tree mid-run ⇒
  `suite: "invalidated"` regardless of exit code. Never report green for a tree that moved during the test.
- Environment: the worktree has no `.venv`/`node_modules` of its own (P2-2 risk). If `TEST_CMD` fails for missing dependencies, that is a RED with a
  readable log, not a skip. Bootstrapping is P2-1's concern, and the gate must not paper over it.
- Concurrency: gates run sequentially (`gate_concurrency = 1`, advisory H5) until parallel gating is measured.

**Deferred alternative (not in P2-3):** gate in an ephemeral detached worktree at the exact sha (`git worktree add --detach`). This removes
drift entirely but costs a dependency bootstrap per gate. Revisit when fan-out has more than two workers.

---

## 3. Commit sha verification against the common git directory

### 3.1 Which repository

All worktrees share one object store. Probe: a commit made in worktree `t5` is visible to `cat-file -e` from the root **and** from
worktree `t6`. So existence can be checked from anywhere, but the supervisor must not depend on where it happens to run. Resolve
the common dir **absolutely**. Probe: from the root, `--git-common-dir` returns the relative string `.git`.

```bash
GIT_COMMON=$(git -C "$REPO_DIR" rev-parse --path-format=absolute --git-common-dir)
git --git-dir="$GIT_COMMON" cat-file -e "${sha}^{commit}"
```

### 3.2 Existence is not provenance (three checks, all required)

Probe: `cat-file -e` accepted **another seat's sha** and **`main`'s sha**. A verdict could cite either and be gated green
against code the seat never wrote.

| # | Check | Command | Rejects |
|---|---|---|---|
| V1 | exists | `git --git-dir="$GIT_COMMON" cat-file -e "$sha^{commit}"` | fabricated / truncated shas |
| V2 | on the seat's branch | `git --git-dir="$GIT_COMMON" merge-base --is-ancestor "$sha" "refs/heads/$GATE_BRANCH"` | another seat's sha (probe: rejected) |
| V3 | is the seat's own work | `git --git-dir="$GIT_COMMON" rev-list --count "$BASE_REF..$sha"` ≥ 1 | base commits (probe: `main`'s sha passes V2, but V3 = 0) |

- `BASE_REF` = the ledger's `base_sha` (P2-2 §3.1), falling back to `base_branch`.
- V2/V3 apply only when `GATE_ISOLATED == true`. Root seats keep today's V1-only check.
- Always expand the short sha to full (`rev-parse "$sha^{commit}"`) before V2/V3 and before writing the record, so dedupe can't
  confuse two 7-char prefixes.
- Any failure ⇒ `suite: "rejected"` with `reason: "not_found" | "not_on_branch" | "not_own_work"`. Escalate to the human, never retire.

---

## 4. Verdict log and telemetry schema additions

### 4.1 `session-verdicts.jsonl` (one JSON object per line, built with `jq -cn`, replacing today's string-concatenated `echo`)

```json
{
  "ts": 1789830000,
  "ticket": 101,
  "seat": "arch-repo",
  "sha": "4e5f6a7c…(full 40)",
  "suite": "green | RED | stale | invalidated | rejected | unresolvable | skipped",
  "reason": null,
  "isolated": true,
  "worktree_dir": "/abs/repo/.herdr-swarm/worktrees/arch-repo",
  "branch": "swarm/repo/arch",
  "base_sha": "82ae09b…",
  "own_commits": 3,
  "gate_cwd": "/abs/repo/.herdr-swarm/worktrees/arch-repo",
  "duration_s": 7.5,
  "exit_code": 0,
  "log": ".herdr-swarm/gate-logs/arch-repo-4e5f6a7.log",
  "verdict": "ARCH DONE #101 4e5f6a7"
}
```

- `worktree_dir`, `branch`, `isolated` are copied from the ledger at gate time. `gate_cwd` is where the suite actually ran; it equals
  `worktree_dir` for isolated seats, and a mismatch in a record is itself a bug signal.
- New fields are **additive**. Readers must tolerate their absence (old records). Existing jq filters (`.ticket`, `.sha`, `.suite`) keep working.
- **Retirement semantics:** only `green` retires a ticket. `RED` asks the seat to fix. `stale`/`invalidated` ask it to re-verdict.
  `rejected`/`unresolvable`/`skipped` escalate to the human. The dedupe "permanent retire" filter (`:142`) must match **only** `green`.
  Today it also retires `skipped`, which contradicts the escalation path added in `5acf8f6`.

### 4.2 Telemetry (`telemetry.py log … suite.verdict`)

Payload gains `worktree_dir`, `branch`, `isolated`, `gate_cwd`, `reason`, `duration_s`. `summary` becomes
`"suite <status> @ <sha7> [<branch>]"` so the Ops stream shows *which tree* was gated. Add one event, `suite.precheck`, emitted for
`stale | invalidated | rejected | unresolvable` with the failing check, so escalations appear in the stream even though no suite ran.

---

## 5. Acceptance (scratch repo; receipt attached to the ticket)

| # | Setup | Expected record |
|---|---|---|
| A1 | v1 ledger / no ledger, root seat | behaves exactly as `82ae09b` (gate in `REPO_DIR`) + new fields with `isolated:false` |
| A2 | isolated arch, clean, verdict at HEAD, passing change | `green`, `gate_cwd == worktree_dir`, `own_commits ≥ 1` |
| A3 | same, with a failing test **only** in the worktree | `RED` (proves the gate runs the worker's code, not root's) |
| A4 | verdict sha from another seat's branch | `rejected / not_on_branch`, suite not run |
| A5 | verdict sha = `main` HEAD | `rejected / not_own_work` |
| A6 | untracked test file present | `stale`; after cleaning, same sha re-verdict → gated |
| A7 | worktree dir deleted, ledger says isolated | `unresolvable`; root **not** tested |
| A8 | worker commits during the gate run | `invalidated` |
| A9 | gate off / `TEST_CMD=none` | `skipped`, escalated, ticket **not** retired, and a later green can still retire it |

`shellcheck` stays at 0 warnings. A3 is the single most important test and must be in the receipt.

## 6. Out of scope

Parallel gates, the ephemeral detached-worktree gate, integration and arbiter gating, dependency bootstrap (P2-1), and
namespacing the verdict protocol for non-arch seats (`DOCS DONE`, `WORKER DONE` in `docs/worktree-swarm.md`). The harvest grep
still matches only `ARCH DONE`. Track that as a follow-up once a second isolated seat exists.
