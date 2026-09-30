# System Vocabulary and Core Concepts (`CONTEXT.md`)

This document defines the foundational vocabulary, architectural invariants, and operational mechanics of the **Universal Herdr Swarm** (`herd-swarm`). 

All human operators, orchestrators (`looper`), implementation agents (`arch`), and review agents (`pm`, `reviewer`) must adhere to these definitions and strictly heed the associated **_Avoid_** warnings.

---

## Core System Vocabulary

### 1. Fail-Closed
The foundational security and correctness invariant requiring that any missing dependency, unconfigured Git remote, unverified test suite, unauthenticated CLI, or failed verification gate halts execution with a non-zero exit code (`1`) rather than making permissive assumptions or substituting synthetic mocks.
- **Implementation**: [`lib/profile.sh`](lib/profile.sh), [`lib/preflight.sh`](lib/preflight.sh), [ADR 0001](docs/adr/0001-fail-closed-profile-and-test-gating.md).
- **_Avoid_**: _Avoid_ falling back to default foreign repositories (such as `Standard-Pentest/kultivait`), synthetic test bypasses (`TEST_CMD="true"`), or silently caching empty/unrunnable test commands. Never allow autonomous modes to run without positive confirmation of a real test suite.

### 2. Nonce Delivery
The communication protocol where extensive agent instructions and standing briefs (3–10 KB) are compiled from templates into local files (`.herdr-swarm/briefs/<seat>.md`) on disk, and delivered to the agent's Herdr terminal via an ultra-compact (<200 bytes) reference prompt followed by a synthetic enter keystroke.
- **Implementation**: [`lib/briefs.sh`](lib/briefs.sh), [ADR 0003](docs/adr/0003-dynamic-seating-and-nonce-brief-delivery.md).
- **_Avoid_**: _Avoid_ dumping raw markdown brief contents directly into the Herdr terminal or prompt command (e.g. `cat "$brief_file" | herdr agent prompt`), which saturates the PTY input buffer, truncates instructions, corrupts terminal escape sequences, and drops prompt submissions.

### 3. Seat Ledger
The durable, machine-readable JSON record stored at `.herdr-swarm/seats.json` capturing the active workspace ID and the exact mapping of every seated agent to its allocated pane ID and runtime engine kind.
- **Implementation**: `.herdr-swarm/seats.json` (runtime state, per target repo), [`lib/lifecycle.sh`](lib/lifecycle.sh), [ADR 0004](docs/adr/0004-safe-workspace-lifecycle-and-seat-ledger.md).
- **_Avoid_**: _Avoid_ relying on ambient environment variables (`$HERDR_WORKSPACE_ID`), terminal focus, or fuzzy workspace searches during teardown; _Avoid_ closing panes indiscriminately, which kills active human shells, dev servers, and unrecorded operator tabs.

### 4. Slug Namespacing
The deterministic identifier transformation (`seat-<slug>`, e.g. `arch-kultivait`, `looper-hinchk-stampede`) ensuring that all seated agents are unique in Herdr's server-global agent registry while strictly satisfying the name grammar `^[a-z][a-z0-9_-]*$`.
- **Implementation**: `slugify()` in [`lib/common.sh`](lib/common.sh), [`lib/config.sh`](lib/config.sh), [ADR 0003](docs/adr/0003-dynamic-seating-and-nonce-brief-delivery.md).
- **_Avoid_**: _Avoid_ bare seat names (`arch`, `pm`, `looper`) which collide across projects in Herdr; _Avoid_ illegal separator characters such as unicode middle dots (`·`), spaces, dots, colons, or uppercase characters that trigger Herdr agent registration errors.

### 5. Suite Gate
The automated execution of the target repository's verified test suite command (`TEST_CMD`), initiated by the supervisor daemon upon detecting an agent completion signal, serving as the mandatory quality boundary for all code changes before a ticket can be retired.
- **Implementation**: [`loop-bot-herd.sh`](loop-bot-herd.sh), [`lib/profile.sh`](lib/profile.sh), [ADR 0001](docs/adr/0001-fail-closed-profile-and-test-gating.md).
- **_Avoid_**: _Avoid_ accepting an agent's conversational claim of completion ("I ran the tests and they pass!") without an independent supervisor suite gate run; _Avoid_ synthetic, unrunnable, or no-op test commands (`true`, `none`, empty string).

### 6. Wayfinder Map
The living, human- and agent-readable markdown artifact (`maps/universal-herdr-swarm.md` and associated `maps/tickets/*.md`) that serves as the single architectural compass, recording project destinations, immutable invariants, accepted decisions, and discrete task tickets with mandatory 3-line preambles.
- **Implementation**: [`maps/universal-herdr-swarm.md`](maps/universal-herdr-swarm.md), [`maps/tickets/`](maps/tickets).
- **_Avoid_**: _Avoid_ undocumented architectural drift, tribal knowledge, untracked changes, or executing tasks that lack explicit Intended Outcome, Done-Criteria, and Verification Step definitions.

### 7. Supervisor Gate
The autonomous supervisor daemon (`loop-bot-herd.sh`) that harvests worker verdict emissions (`ARCH DONE #<ticket> <sha>`), applies exact-match `(ticket, sha)` deduplication via `jq`, triggers the Suite Gate, records structured JSONL verdicts, and alerts the orchestrator.
- **Implementation**: [`loop-bot-herd.sh`](loop-bot-herd.sh), [ADR 0002](docs/adr/0002-exact-sha-supervisor-deduplication.md).
- **_Avoid_**: _Avoid_ naive substring grepping over verdict logs (which mistakenly treats `#23` as `#230`); _Avoid_ permanent ticket lockout on `RED` (failed) verdicts, which prevents agents from submitting new commit SHAs under the fix-and-reverdict protocol.

### 8. Arbiter Integration & CAS Merge
The asynchronous, off-branch integration pipeline that serializes and pre-gates passing commits from isolated worker branches onto a dedicated staging ref (`refs/heads/swarm/<slug>/integration`) via Compare-and-Swap (CAS) fast-forward updates before promotion to the base branch (`main`). Green commits enqueue to `.herdr-swarm/integration.jsonl` (`arbiter_enqueue_and_drain`), auto-drain asynchronously under a PID-tracked file lock (`.herdr-swarm/arbiter.lock`), execute the verified suite in a detached worktree (`.herdr-swarm/worktrees/arbiter-<slug>`), and record durable integration evidence without head-of-line blocking. Promotion to `main` remains sovereign-human-only via `arbiter_promote --confirm` (or an active session grant).
- **Implementation**: [`lib/arbiter.sh`](lib/arbiter.sh) (`arbiter_enqueue`, `arbiter_drain`, `arbiter_promote`), [`loop-bot-herd.sh`](loop-bot-herd.sh) (`arbiter_auto_drain`), [ADR 0009](docs/adr/0009-arbiter-branch-integration-and-cas-merge.md), [ADR 0014](docs/adr/0014-arbiter-drain-automation.md).
- **_Avoid_**: _Avoid_ merging worker branches directly into `main`; _Avoid_ running synchronous arbiter drains within the supervisor poll loop; _Avoid_ autonomous promote or push actions without human confirmation or a valid session grant; _Avoid_ fuzzy or automatic merge conflict resolution during drain (conflicts must fail closed, mark `conflict` in the queue, and return to the worker).

### 9. Worktree Isolation
The operational floor topology separating root orchestrator seats from autonomous implementation workers using dedicated Git worktrees (`.herdr-swarm/worktrees/<seat>`). Root coordinators (`looper`, `pm`) operate in the primary checkout (`$PWD`) on `main`, while worker engines (`arch-1`, `arch-2`, `pi`) operate in isolated worktrees checked out to private task branches (`swarm/<slug>/<seat>`), sharing the underlying `.git` object database with zero index lock contention (`0/240` commit collision benchmark). Worktrees are tracked in `.herdr-swarm/seats.json` (v2 schema) with porcelain locking (`git worktree lock`), pre/post-run drift validation, tracked checkpoint branches on dirty teardown, and non-destructive untracked file salvage (`.herdr-swarm/salvage/<seat>/`).
- **Implementation**: [`lib/worktree.sh`](lib/worktree.sh) (`worktree_provision`, `worktree_prune`, `worktree_reconcile`), [`lib/lifecycle.sh`](lib/lifecycle.sh), [`loop-bot-herd.sh`](loop-bot-herd.sh) (`resolve_seat_gate`), [ADR 0006](docs/adr/0006-git-worktree-worker-isolation.md), [ADR 0007](docs/adr/0007-split-pane-cwd-order-and-ledger-v2.md), [ADR 0008](docs/adr/0008-supervisor-worktree-suite-gating-and-drift.md), [ADR 0010](docs/adr/0010-worktree-teardown-lifecycle-and-salvage.md).
- **_Avoid_**: _Avoid_ running multiple concurrent implementation agents in a shared repository checkout; _Avoid_ falling back to the root checkout when an isolated worktree is missing or mismatched (which causes false-green suite gates); _Avoid_ deleting unmerged worker branches or dirty worktrees during teardown without salvage checkpoints; _Avoid_ auto-enqueuing commits from root-checkout workers (only isolated worktree seats auto-enqueue).

### 10. Partition & Lease
The static task partitioning and dynamic concurrency-control protocol that guarantees disjoint file access among concurrent workers. Tickets declare target paths using single-line `owns:` YAML frontmatter in `maps/tickets/*.md`. Prior to dispatch, `partition_check` evaluates candidate ownership against active ticket assignments, returning clear (`0`), exclusive-clear (`2`, runs alone for unowned tickets), or blocked (`1`). Upon dispatch, `lease_acquire` records the active reservation in `.herdr-swarm/leases.json`. Crucially, leases are tied to *integration evidence*, not verdict emission: `lease_release_integrated` holds leases until the commit reaches `integrated` or `promoted` status in `integration.jsonl`, preventing downstream workers from mutating files that are still queued for arbiter merging.
- **Implementation**: [`lib/partition.sh`](lib/partition.sh) (`owns_normalize`, `partition_check`, `lease_acquire`, `lease_release`), [`loop-bot-herd.sh`](loop-bot-herd.sh) (`lease_release_integrated`), [ADR 0012](docs/adr/0012-task-partitioning-and-disjoint-dispatches.md).
- **_Avoid_**: _Avoid_ releasing path leases upon green test verdict (`ARCH DONE`) before changes have integrated to the integration branch; _Avoid_ dispatching tickets with overlapping `owns:` boundaries to concurrent workers; _Avoid_ omitting `owns:` frontmatter on scoped tickets (which forces exclusive single-ticket execution).

### 11. Autonomous Reviewer Loop
The dual-phase adversarial audit protocol that gates verified commits before they can enqueue to the Arbiter. When enabled in `swarm.config.toml` (`[reviewer] loop = true`), passing the Suite Gate does not immediately enqueue; it dispatches the commit SHA to `reviewer` under a durable state machine (`.herdr-swarm/reviews.json`). The reviewer audits the git diff against standing security, robustness, and architectural standards, emitting either `REVIEW VERDICT #<ticket> <sha> PASS` (triggering arbiter enqueue) or `BLOCK` accompanied by a structured markdown report in `.herdr-swarm/reviews/<ticket>-<sha>.md`. Critique turns return to the worker's worktree for refinement up to a strict budget ceiling (`max_rounds = 2`). If critique rounds are exhausted without approval, the loop halts with an `ALERT_BLOCKED` directive, blocking arbiter enqueue until human intervention.
- **Implementation**: [`lib/lifecycle.sh`](lib/lifecycle.sh) (`review_loop_on_gate_green`, `review_loop_on_review_verdict`, `review_loop_status`), [`loop-bot-herd.sh`](loop-bot-herd.sh) (`_review_directives`, `worker_feedback`), [`tests/test_review_loop.sh`](tests/test_review_loop.sh). *(Note: Shipped in REV-1–5 and proven in PROVE-3; no standalone ADR exists yet).*
- **_Avoid_**: _Avoid_ bypassing adversarial review when `reviewer.loop = true` is configured; _Avoid_ unbounded critique cycles between worker and reviewer by strictly capping turns at `max_rounds`; _Avoid_ inlining multi-kilobyte critique text directly into terminal input (always pass pointer references to `.herdr-swarm/reviews/<ticket>-<sha>.md`).

### 12. Headless Batch Drain
The unattended batch execution mode (`bin/stampede headless [--max-tickets N] [--timeout M]`) that drains queued backlog tickets without opening Herdr panes, creating multiplexer sessions, or requiring a graphical display. Implemented via direct background subprocess management (`lib/headless.sh`), it invokes vendor CLIs (`claude -p`, `opencode run`, `agy -p`) directly inside provisioned worktrees with output redirected to `.herdr-swarm/logs/<seat>.log`. Sourcing supervisor gate mechanics under `HEADLESS_MODE=1` with the reviewer loop disabled (`CONFIG_REVIEW_LOOP=0`), it enforces three unattended safety closures: (1) a re-verdict ceiling (`[headless] max_verdict_attempts`, default 2) moving stuck tickets to `DEAD_LETTER` and releasing leases, (2) hard process timeouts (`resolve_timeout`) with stale pidfile eviction (`headless_reap`), and (3) structured `.herdr-swarm/dead-letter.jsonl` failure logging with non-zero CI exit codes (`1` for dead letters, `3` for batch timeout). Headless mode is strictly **additive**: interactive pane mode (`stampede up`) remains permanently preserved.
- **Implementation**: [`lib/headless.sh`](lib/headless.sh) (`headless_spawn`, `headless_status`, `headless_kill`, `headless_reap`), [`lib/cli/stampede-headless.sh`](lib/cli/stampede-headless.sh), [`loop-bot-herd.sh`](loop-bot-herd.sh) (`_headless_seat_output`, `worker_feedback`, `_headless_deadletter`), [ADR 0015](docs/adr/0015-headless-batch-drain-mode.md).
- **_Avoid_**: _Avoid_ treating headless mode as a replacement for interactive multi-agent collaboration; _Avoid_ running headless workers on the root checkout; _Avoid_ unconstrained batch execution without `--max-tickets` or `--timeout` boundaries; _Avoid_ swallowing unattended failures (CI pipelines must observe non-zero exit codes on dead letters).

### 13. Session-Scoped Promote Grant
The time-bounded, human-authorized delegation mechanism (`bash lib/arbiter.sh grant-session [--ttl SECONDS]`) that permits autonomous promote and push operations for the duration of an active session without requiring `--confirm` or human intervention on every individual promote call. Creation and revocation of the grant file (`.herdr-swarm/promote-grant.json`) enforce the same non-agent pane check (`_arb_promote_pane_check()`) as `arbiter_promote` itself: an agent seat can never grant itself authorization. Every session starts ungranted; grants expire automatically after their TTL (default: 4 hours) or upon explicit revocation (`arbiter_revoke_session`), immediately restoring the requirement for sovereign human promote execution.
- **Implementation**: [`lib/arbiter.sh`](lib/arbiter.sh) (`arbiter_grant_session`, `arbiter_revoke_session`), [`maps/tickets/grant-1-session-promote-authorization.md`](maps/tickets/grant-1-session-promote-authorization.md), [`briefs/looper.in.md`](briefs/looper.in.md). *(Note: Shipped in GRANT-1; no standalone ADR exists yet).*
- **_Avoid_**: _Avoid_ permanent or standing configuration toggles for promote authorization; _Avoid_ agents attempting to generate or modify `.herdr-swarm/promote-grant.json` directly or via cross-pane injection; _Avoid_ assuming a grant is active without verifying that `_arb_grant_valid` evaluates to true and is unexpired.

### 14. Fail-Closed Ref Resolution
The architectural invariant requiring that any Git reference resolution operation for critical integration or base branches must verify that the ref already exists, and must immediately refuse execution if it is absent, rather than silently falling back to a default branch or synthesizing a new ref from a fallback base commit. Discovered during the `ARB-SLUG-1` incident—where a slug naming divergence caused `arbiter_drain` to silently create a phantom integration branch `swarm/hinchk-stampede/integration` rooted at `main`, forking history—this invariant establishes that integration branches (`swarm/<slug>/integration`) must be initialized explicitly and once via `arbiter_init_ref [base]`. If an expected integration ref is missing, all drain and enqueue operations must fail closed with actionable remediation guidance.
- **Implementation**: [`lib/arbiter.sh`](lib/arbiter.sh) (`arbiter_init_ref`, `arbiter_drain`, `arbiter_promote`), [`loop-bot-herd.sh`](loop-bot-herd.sh) (`PROJECT_SLUG="${SWARM_CONFIG_NAME:-$PROJECT_SLUG}"`), [`maps/tickets/arb-slug-1-fail-closed-integration-ref.md`](maps/tickets/arb-slug-1-fail-closed-integration-ref.md). *(Note: Shipped in ARB-SLUG-1; no standalone ADR exists yet).*
- **_Avoid_**: _Avoid_ permissive "create-if-missing" ref updates on integration or base branches; _Avoid_ implicit branch creation rooted at `HEAD` or `main` during background automated passes; _Avoid_ deriving canonical ref slugs from volatile or seat-namespaced environment variables instead of the authoritative project configuration (`[swarm] name`).

---

## Architectural Interaction Matrix

```
                      ┌────────────────────────┐
                      │  swarm.config.toml     │
                      │  (Registry of Seats)   │
                      └───────────┬────────────┘
                                  │
                                  ▼
┌──────────────────┐    ┌────────────────────┐    ┌──────────────────────┐
│  Preflight Gate  ├───>│  Dynamic Seating   ├───>│ Nonce Brief Delivery │
│ (9-Point Matrix) │    │ (Slug Namespacing) │    │  (<200b Pointer)     │
└──────────────────┘    └─────────┬──────────┘    └──────────────────────┘
                                  │
                                  ▼
                        ┌───────────────────┐
                        │    Seat Ledger    │
                        │   (seats.json)    │
                        └─────────┬─────────┘
                                  │
                                  ▼
                        ┌───────────────────┐
                        │ Seat Verification │
                        │  (Readiness Gate) │
                        └─────────┬─────────┘
                                  │
                                  ▼
┌──────────────────┐    ┌───────────────────┐    ┌──────────────────────┐
│  Wayfinder Map   │<───│  Worker Execution │───>│   Supervisor Gate    │
│ (Local Tickets)  │    │ (Worktree Seats)  │    │ (Exact-SHA Dedupe)   │
└──────────────────┘    └───────────────────┘    └──────────┬───────────┘
                                                            │
                                                            ▼
                                                 ┌──────────────────────┐
                                                 │      Suite Gate      │
                                                 │ (Fail-Closed Test)   │
                                                 └──────────┬───────────┘
                                                            │ (green)
                                                            ▼
                                                 ┌──────────────────────┐
                                                 │ Reviewer Loop Gate   │
                                                 │ (PASS / BLOCK Rounds)│
                                                 └──────────┬───────────┘
                                                            │ (PASS)
                                                            ▼
                                                 ┌──────────────────────┐
                                                 │ Arbiter CAS Pipeline │
                                                 │ (swarm/.../integ)    │
                                                 └──────────┬───────────┘
                                                            │
                                                            ▼
                                                 ┌──────────────────────┐
                                                 │ Sovereign Human Gate │
                                                 │ (promote --confirm / │
                                                 │  session grant)      │
                                                 └──────────────────────┘
```

---

## Key Invariants & Safety Protocols

1. **Role Separation**: `looper` orchestrates and verifies; implementation code is authored exclusively by `arch`.
2. **Git Remote Safety**: Remote git operations (`push`, release tags) require explicit human driver approval (or an active session-scoped promote grant).
3. **Workspace Discipline**: Pane routing must always address explicit workspace-prefixed IDs (`wX:pY`) obtained from tab anchors; scripts must **never** use `--current`.
4. **Prompt Maturity**: All task assignments and kickoff directives must explicitly state **Intended Outcome**, **Explicit Done-Criteria**, and **Verification Step**.
5. **Sovereign Human Promotion**: Advancing the base branch (`main`) is reserved exclusively for the human driver via `promote --confirm` or an explicit `grant-session` authorization. Agents must never pass `--confirm` or self-authorize.
6. **Partition Disjointness & Lease Integrity**: Concurrent workers must operate on disjoint path sets defined by `owns:`; path leases remain held until changes are integrated into `swarm/<slug>/integration`.
7. **Zero Cross-Pane Evasion**: Agents must never use cross-pane or inter-process injection (`herdr pane run`, `send-text`, `send-keys`) to route around gates or execute forbidden actions in other panes.
