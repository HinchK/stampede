# Changelog

All notable changes to Stampede are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The tree is
pre-1.0: the public surface is not frozen.

`make version-check` fails when the top entry below disagrees with
`VERSION`. Tagging is a human act — nothing in this repository pushes.

## [Unreleased]

### Added
- `stampede autopilot <repo> on|off|status` (#AUTOPILOT-1): one command that
  composes the existing switches into a fast mode — quiet attention,
  deterministic intake, a per-pass arbiter drain, and a TTL'd promote grant
  so greens integrate and promote locally without the manual ceremony. The
  suite gate, the state locks, the agent-pane promote block, and pushing
  stay enforced; `off` restores the previous attention mode. `promote` is
  now a silent no-op when the base branch is already at the integration tip.

- Four borrows from the 2026-11-07 prior-art survey:
  - A GREEN gate records files outside the ticket's `owns:` line in
    `owns-violations.jsonl` (the existing `partition_drift_check`, now
    called). Never blocking.
  - A RED gate first runs the suite once at the worker's merge-base; when
    the base fails too the verdict is `base_red`, the human is notified,
    and the worker is not sent into a repair loop (a headless batch
    dead-letters it with that reason). A base that cannot run the suite at
    all (exit 126/127) attributes nothing and stays an ordinary RED.
  - A ticket whose `blocked_by:` / `depends_on:` names an unresolved (or
    unknown) ticket is not dispatched, interactively or headless.
  - A failed `herdr agent prompt` warns instead of vanishing behind
    `|| true` at the six kickoff/notice/feedback sites.

### Fixed
- One project slug (#166, ADR 0019): the launcher, supervisor, standby,
  verify roster, `stampede arbiter` and `stampede autopilot` all take the
  slug from `[swarm] name` via `config_project_slug`, falling back to the
  profile `REPO` or directory name only when no name is set. Agent names,
  seat branches and the integration ref can no longer split across
  `swarm/<repo-slug>/…` and `swarm/<name>/…`.
- Gate suites run hermetically (#164): the arbiter's integration gate and
  the supervisor's sync, async and base-attribution gates run `TEST_CMD`
  through `gate_exec`, which strips `REPO_DIR`, `STATE_DIR`, the slug,
  `SWARM_CONFIG_NAME`, `STAMPEDE_CONFIG*` and `HERDR_*` so a suite cannot
  read the live swarm's state instead of its fixtures, and gates in a
  `gate-tmp/` path that carries no "arbiter" substring. `test_frontier_launch.sh` matches arbiter invocations, not the
  substring "arbiter" in the gate's own checkout path.
- `arbiter drain` no longer halts on the first conflict or
  `integration_red` (#172): either outcome resets the ref and worktree, so
  independent work queued behind it integrates in the same drain. Anything
  else (a record left `queued`, a lost CAS or status write, a superseded
  record) still stops the pass; drain also announces each gate (#171).
- A rejected review verdict anchor is harvested exactly once (#REV-ALERT-1,
  audit Must-fix #1): pane scrollback persists across supervisor passes, and
  a rejected anchor that was never recorded in the seen-file re-alerted —
  and in non-bounded mode re-prompted the looper agent — every 30 seconds
  forever, appending fail-closed history to reviews.json on each pass.
  Rejections are now marked seen, except the one repairable case (awaiting
  review with no reviewer assigned yet), which stays re-harvestable for the
  legacy redispatch path.
- Legacy numeric ticket rows can leave the integration queue again (#ARB-NUM):
  pre-ARB-STR enqueues wrote numeric ids, and the queue's own type-strict
  comparisons never matched them — status writes silently no-opped and every
  drain re-processed the record, adding an empty merge commit per pass. All
  queue-write comparisons now compare ticket ids as strings.

## [0.6.0] — 2026-11-05 (orchestration safety and bounded looper)

### Fixed
- Review verdicts require the assigned independent sender; self-reviewing
  quota failover stays deferred, and legacy pending reviews are redispatched.
- Queue writes are serialized, preserve compact JSONL, and keep arrivals and
  superseded candidates safe during an integration gate. Promotion bookkeeping
  covers only commits included in the promoted tip.
- Integration gates reject HEAD or visible file drift even after a passing test.
- Setup and attention share legacy/renamed architect role interpretation.
- Inline gates continue through the same review and enqueue policy as background gates.

### Changed
- **Bounded looper is a critical seated agent** (LOOPER-1): setup's default
  `attention.bounded_looper = true` launches the configured looper kind
  (AGY this release) like every other seat, or fails closed. A stale
  agentless/shell looper ledger fails `verify`. Worklog, troubleshooting,
  and handoff panes stay model-free.
- **Profile placeholders rejected:** cached `REPO="none"` is invalid;
  local-only uses `REPO_LOCAL_ONLY=1`. `TEST_CMD` of `""`, `none`, or
  `true` is not runnable. `up` and `status` warn when the suite gate is
  unavailable.

## [0.5.0] — 2026-10-05 (multi-provider UX, review loop, and headless batch drain)

### Added
- **Headless Batch Drain Mode** (`bin/stampede headless`): unattended queue
  drainer running worker CLIs as direct background subprocesses in isolated
  worktrees without opening Herdr panes or requiring display servers (HEADLESS-1..7,
  ADR 0015).
- **Headless Mode Safety & Hardening**: deterministic queue discovery over
  backlog tickets, in-batch critique loop on first RED, wall-clock timeout
  wrapping with SIGKILL escalation (rc 124), non-zero exit (rc 1) on dead
  letters, structured `.herdr-swarm/dead-letter.jsonl` with explicit worker log
  pointers, environment variable precedence (`emit_env_wins`), and worktree rc
  verification (HL-WT-1, HL-CFG-1, HL-RED-1, HL-TMO-1, HL-DOCS-1, PROVE-HEADLESS-1).
- **Headless Live-Seat Isolation**: headless workers are namespaced (`headless-<seat>`) so their ledger entry can never collide with a live interactive seat's record in `.herdr-swarm/seats.json` (HL-LEDGER-1).
- **Headless Dead-Letter Batch Scoping**: dead-letter counting is scoped to the active batch run (a since-index on the append-only log) rather than the stable per-project session, so historical dead letters no longer fail later all-green batches (HL-DL-1).
- **Headless Live Proof**: `stampede headless` proven end-to-end on this repository's own real backlog with full receipts, including two live-only defects found and fixed -- a stale nested worktree correctly refused, and a stale provider-model id in the project's `.opencode/opencode.json` (HORIZON-2, `docs/findings/headless-live-proof.md`).
- **`stampede quota`'s Antigravity/Gemini (agy) kind probe**, read-only, via pane-output scanning (QUOTA-1).
- **User-facing documentation for `stampede headless`** -- user guide section and README run-mode entry (HORIZON-4).
- **Autonomous Reviewer Loop**: multi-turn critique cycles (`[reviewer] loop = true`),
  structured `REVIEW VERDICT #<ticket> <sha> <PASS|BLOCK>` anchors, durable
  findings artifacts in `.herdr-swarm/reviews/<ticket>-<sha>.md`, and
  `ALERT_BLOCKED` budget ceilings (REV-1..5, PROVE-2, PROVE-3).
- **Session-Scoped Promote Authorization**: time-bounded human delegation
  (`bash lib/arbiter.sh grant-session [--ttl SECONDS]`) with
  `.herdr-swarm/promote-grant.json`, reusing `_arb_promote_pane_check()` to
  ensure agent seats cannot self-authorize (GRANT-1, DECISION-1).
- **Automated Arbiter Drain Pipeline**: `arbiter_enqueue_and_drain` background
  drain automation in supervisor, child process PID logging, and crash-and-evict
  stale lock recovery (PROVE-4, PROVE-5, PROVE-7, ADR 0014).
- **Partition & Ref Integrity**: fail-closed integration ref verification
  (`arbiter_init_ref [BASE]`) and canonical slug resolution (ARB-SLUG-1),
  active-ticket conflict rejection in `lease_acquire()` (PART-2), and superseded
  ticket handling (PART-1, SYNC-2).
- **Developer Tooling & Sync**: `scripts/repo-state.sh` repository summary (DOG-17),
  `scripts/ci-local.sh` with pinned ShellCheck version verification (DOG-18),
  `stampede quota` provider quota probing (PUB-9), two-way GitHub issue
  synchronization (SYNC-1, SYNC-2), and empirical trust-tax telemetry
  measurements (TRUST-1).
- `bin/stampede` unified entrypoint; lifecycle commands delegate to
  `herdr-loop-swarm.sh` unchanged, other commands dispatch by convention
  to `lib/cli/stampede-<cmd>.sh` (PUB-1).
- Provider registry (`lib/providers.sh`) and `stampede doctor`: per-seat
  OK/MISSING/SKIP provider health plus the 9-point preflight; enabled
  seats decide the exit code (PUB-2).
- `examples/demo-repo`: real test suite and a one-verified-verdict
  walkthrough (PUB-4).
- `VERSION`, this changelog, and `stampede version` (PUB-5).
- Rich status inspection (`stampede status`) with review loop aggregation (PUB-11).
- Provider fallback chains and cross-provider reviewer seating (PUB-6, PUB-8).

### Changed
- Promotes and session grants enforce `_arb_promote_pane_check()`, refusing
  execution from agent-occupied panes (GATE-1, GATE-2, ADR 0009).
- Standing worker briefs explicitly prohibit cross-pane injection via
  `herdr pane run`, `send-text`, or `send-keys` (BRIEF-1).
- `CONTEXT.md` expanded with vocabulary and `_Avoid_` entries for all
  seven post-Phase 1 architectural concepts (CONTEXT-1).
- Ledger boolean normalization across launcher and supervisor (SUPER-1).
- **Headless batch review boundary formalized as an accepted limit**: batch quality is the suite gate plus mechanical safety ceilings only, never a reviewer pass -- review stays an interactive-herd-only feature (ADR 0016, HORIZON-3).

## [0.4.0] — public readiness (dogfood waves 1–5)

### Changed
- Zero-trust README lede; token-claim relabelled as modelled, not
  measured (DOG-4, DOG-5).
- kultivait/pi local engine fully optional and disabled by default;
  proxy and credentials are config data, never launcher hardcode
  (DOG-7, PROXY-GATE).
- 48 tracked markdown files swept to repo-relative links (DOG-9).

### Added
- Apache-2.0 `LICENSE` (DOG-2); `CONTRIBUTING.md` and `SECURITY.md`
  (DOG-6); CI on macOS and Ubuntu running `make check` on every push and
  PR with pinned shellcheck (DOG-3, DOG-14).
- Centralized tomllib-capable interpreter resolution (`lib/pyenv.sh`)
  and timeout(1) resolution with actionable remediation (DOG-1, DOG-15).
- Hermetic `lib/gh_sync.sh` test suite (DOG-8); fresh-clone partition
  deadlock fix (DOG-11); looper promote guardrail (`--confirm` /
  `PROMOTE_CONFIRM=1`) and arbiter anchored to the orchestrator root
  (DOG-12, DOG-13).

## [0.3.0] — concurrent fan-out (Phase 3)

### Added
- Multi-worker seating from `swarm.config.toml` (heterogeneous kinds,
  worktree isolation per implementation seat).
- `lib/partition.sh`: single-line `owns:` grammar, overlap refusal, and
  path leases held until integration (P3-2, ADR 0012).
- Asynchronous supervisor suite gating with durable job records,
  `(ticket, sha)` dedupe, concurrency cap, mid-gate invalidation
  (P3-3, ADR 0013).
- String ticket ids end-to-end in the arbiter queue (ARB-STR).
- Live ANSI telemetry streaming in the Ops pane (`lib/telemetry.py`).

## [0.2.0] — worktree isolation (Phase 2)

### Added
- `lib/worktree.sh` provisioning with porcelain locking, dirty tracked
  checkpoints, salvage-preserving teardown, stale-branch gating
  (P2-1, P2-H, ADR 0006/0010).
- Supervisor gates seats in their own worktrees with pre/post drift
  detection (P3-3 specs, ADR 0008).
- `lib/arbiter.sh`: gated-sha merges onto `swarm/<slug>/integration`
  with compare-and-swap ref updates and human-only promote (P2-4,
  ADR 0009).
- Dynamic TOML seating, slug namespacing, nonce brief delivery, durable
  seat ledger v2 (T-INT wave, ADR 0003/0007).

## [0.1.0] — sequential swarm (Milestone 1)

### Added
- Fail-closed project profiling and test gating; synthetic gates
  (`true`, `none`, empty) rejected (ADR 0001).
- Supervisor verdict harvesting with exact-sha dedupe and fix-and-
  re-verdict on new commits (ADR 0002).
- 9-point preflight matrix and post-seating readiness verification
  (ADR 0005); safe workspace lifecycle resolved by physical pane cwd
  (ADR 0004).
- Aggregate `make test` / `make lint` / `make check` gates; bash 3.2
  platform floor enforced (#TEST-AGG, #BASH32-FLOOR).
