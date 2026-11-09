# The `lib/` guide — what every module is for

One canonical answer to "how is `lib/<module>` supposed to be used?": what each of the 31
files under `lib/` is for, who consumes it, its contract (sourced vs executed, subcommands
when it is an entry point), and its public surface. Written for any seat, contributor, or
curious human; documents the tree **as it is** at commit `e6fc188` (2026-11-08, LIBDOC-1).

Truth bar: every function named below greps in its cited module, every consumer list was
re-derived from `grep` over the tree, and the coverage table matches `ls lib/*.sh lib/*.py
lib/cli/*.sh` exactly (the ticket's verification diff). Underscore-prefixed helpers are
summarized as a count — they are not surface. Source material: the helper seat's inventory
(`.herdr-swarm/research/2026-11-08-lib-modules-inventory.md`, session state), corrected
against the tree where it had drifted.

## How it composes

**Config → environment → launcher.** `swarm.config.toml` is the single source of seat truth.
`lib/pyenv.sh` resolves a tomllib-capable Python interpreter; `lib/config.sh` parses the TOML
through it and emits `shlex.quote`d `export SEAT_*` / `CONFIG_*` lines that
`herdr-loop-swarm.sh` evals. Slug and paths travel as `sys.argv`, never interpolated into
Python source. Adding or removing a seat is a TOML edit — seat names are never hardcoded in
shell.

**Profile is fail-closed.** Before any workspace mutation, `lib/profile.sh` detects the
target repo's `REPO`, `ECOSYSTEM`, `TEST_CMD` and `DOCS_DIR` and caches them in
`<target>/.herdr-swarm/profile.env`. No test runner (`test_cmd_is_runnable` rejects `""`,
`none`, `true`) means no launch — a synthetic gate would green-light everything.

**Seating order is a rule, not a preference.** `herdr agent start` has no `--cwd`, so an
isolated seat must be provisioned before its pane exists: `lib/worktree.sh`
`worktree_provision` → `lib/layout_engine.sh` `split_pane` (with the worktree as cwd) →
`lib/providers.sh` `providers_start_agent` → seat ledger entry. `bin/stampede` reaches every
`lib/cli/stampede-<cmd>.sh` by convention dispatch — new commands land as new files, and the
dispatcher never needs to know the list.

**Two run modes, one spine (ADR 0015).** The interactive pane mode (launcher +
`loop-bot-herd.sh watch`) and the headless batch mode (`lib/cli/stampede-headless.sh` +
`lib/headless.sh`) share the same modules — config, profile, common, worktree, partition,
arbiter, attention, telemetry. The only designed difference is the seam where seat output is
read from: Herdr panes in one mode, subprocess logs in the other (HEADLESS-4). Everything
downstream of that seam — verdict harvest, the suite gate (`lib/common.sh` `gate_exec`,
hermetic), the review loop (`lib/lifecycle.sh`), the arbiter queue — is identical code.

**The integration line.** Green gates enqueue through `lib/arbiter.sh`, whose drain gates and
integrates verified commits onto `swarm/<slug>/integration` (ADR 0019: one slug names seats,
branches and the integration ref). Reaching the base branch is a human act — `arbiter_promote`
with or without `--pr`, or the time-boxed grant that `lib/cli/stampede-autopilot.sh` can mint.
`lib/partition.sh` keeps concurrent seats disjoint (ticket `owns:` lines plus leases);
`lib/attention.py` decides what the looper looks at next and throttles alerts;
`lib/telemetry.py` records the whole story as local JSONL (zero network).

## Coverage table (31 files)

| `arbiter.sh` | core | CAS merge queue: gate, integrate, promote |
| `attention.py` | exec | looper attention policy: blockers, throttle, next ticket |
| `briefs.sh` | core | render seat briefs from templates, nonce delivery |
| `cli/stampede-arbiter.sh` | cli | `stampede arbiter` — human wrapper on the arbiter |
| `cli/stampede-attention.sh` | cli | `stampede attention` — read/manage attention state |
| `cli/stampede-autopilot.sh` | cli | `stampede autopilot` — fast-mode switch composition |
| `cli/stampede-doctor.sh` | cli | `stampede doctor` — diagnostics with remedies |
| `cli/stampede-headless.sh` | cli | `stampede headless` — unattended batch runner |
| `cli/stampede-init.sh` | cli | `stampede init` — generate swarm.config.toml |
| `cli/stampede-quota.sh` | cli | `stampede quota` — provider headroom readout |
| `cli/stampede-setup.sh` | cli | `stampede setup` — guided config wizard |
| `cli/stampede-status.sh` | cli | `stampede status --rich` — trust dashboard |
| `cli/stampede-version.sh` | cli | `stampede version` — version + release status |
| `cli/stampede-worktree.sh` | cli | `stampede worktree` — audit/sweep worktrees |
| `common.sh` | core | shared helpers: slugify, gate_exec, timeouts, evidence |
| `config.sh` | core | TOML → safely-quoted environment exports |
| `gh_sync.sh` | exec | tickets ↔ GitHub issues reconciliation |
| `headless.sh` | exec | batch subprocess harness, reaping, dead-letters |
| `layout_engine.sh` | core | herdr tabs and 2×2 pane layout |
| `lifecycle.sh` | core | workspace discovery, review loop, verify, teardown |
| `partition.sh` | core | owns: parsing, overlap checks, leases, drift |
| `preflight.sh` | core | 9-point dependency verification before launch |
| `profile.sh` | core | target-repo detection, fail-closed profile cache |
| `providers.sh` | core | provider kinds → binaries, chains, launches |
| `pyenv.sh` | core | resolve a tomllib-capable python3 |
| `quota.sh` | exec | quota probing and the dispatch gate |
| `roles.py` | core | canonical seat-role mapping (current + legacy) |
| `setup.py` | exec | interactive guided config authoring |
| `standby.sh` | core | standby orchestrator for quota failover |
| `telemetry.py` | exec | local JSONL event log + ANSI live stream |
| `worktree.sh` | core | worktree provision/lock/prune/reconcile |

## Core orchestration & integration

### `lib/arbiter.sh`

Transactional merge queue and integration engine. Integrates suite-verified commits onto
`swarm/<slug>/integration` without touching the base branch; promote to base is human-gated.
Touch it when integration ordering, the queue's JSONL records, or the promote gate change.

- **Consumers:** `herdr-loop-swarm.sh`, `loop-bot-herd.sh` (drain/promote/grant paths),
  `lib/cli/stampede-arbiter.sh`, `lib/cli/stampede-autopilot.sh`, `lib/headless.sh`,
  `lib/standby.sh`; briefs reference its path via `ARBITER_BIN` (`lib/briefs.sh:87`).
  Tests: `test_arbiter.sh`, `test_async_gate.sh`, `test_autopilot.sh`.
- **Contract:** sourced for its functions; directly executable —
  `lib/arbiter.sh record|enqueue|enqueue-and-drain|drain|promote [--pr] [--confirm]|grant-session|revoke-session|init-ref|pr-body [dir]`.
  15 underscore-prefixed helpers (not surface).
- **Public functions:**
  - `arbiter_lock` / `arbiter_unlock` — guarded lock over state mutations (stale-holder reaping included).
  - `arbiter_enqueue` — append a `(ticket, seat, sha)` queued record; refuses a sha another ticket holds (ARB-DUP-1).
  - `arbiter_enqueue_and_drain` — enqueue then drain in one call.
  - `arbiter_queued_count` — number of queued records.
  - `arbiter_drain` — gate each queued tip, fast-forward the integration ref, record outcomes; keeps going past conflicts (#172).
  - `arbiter_pr_body` — render the PR body file from queue history.
  - `arbiter_grant_session` / `arbiter_revoke_session` — time-boxed promote grant and its revocation.
  - `arbiter_promote` — push integration to base (human gate; `--pr` opens a PR).
  - `arbiter_init_ref` — create/repair the integration ref at base.

### `lib/worktree.sh`

Lifecycle manager for git worktrees: isolated seat provisioning on `swarm/<slug>/<seat>`,
lock tracking, and prune that checkpoints tracked edits and salvages untracked files before
removal. Touch it when seat isolation or teardown safety changes.

- **Consumers:** `herdr-loop-swarm.sh`, `lib/headless.sh`, `lib/lifecycle.sh` (teardown),
  `lib/cli/stampede-headless.sh`. Tests: `test_worktree.sh`, `test_partition.sh`,
  `test_async_gate.sh`.
- **Contract:** sourced; directly executable — `lib/worktree.sh provision <seat> <slug>
  [base] [dir] | prune <seat> <slug> [force] [dir] | reconcile [dir]`. Three underscore
  helpers (not surface).
- **Public functions:**
  - `worktree_provision` — create/adopt a seat worktree on its branch; `WORKTREE_ADOPT_BRANCHES=1` adopts a stale branch.
  - `worktree_is_locked` / `worktree_is_dirty` — cheap predicates for callers deciding teardown safety.
  - `worktree_prune` — unlock, checkpoint (`add -u`, never `-A`), salvage untracked, remove; branch always survives.
  - `worktree_reconcile` — report and clean prunable metadata for vanished directories.

### `lib/partition.sh`

Keeps concurrent seats off each other's files: `owns:` frontmatter parsing and overlap
checks, the lease layer that makes dispatch exclusive, post-GREEN drift checking, and the
`suggest` helper that drafts an `owns:` line from a diff. Touch it when dispatch blocking,
leases, or owns semantics change.

- **Consumers:** `loop-bot-herd.sh` (dispatch guard, release pass), `lib/headless.sh`.
  Tests: `test_partition.sh`, `test_setup.sh`, `test_standby.sh`.
- **Contract:** sourced; directly executable — `lib/partition.sh check | can-dispatch |
  lease acquire|release|list|reconcile | suggest | drift-check | overlaps …`. Ten
  underscore helpers (not surface).
- **Public functions:**
  - `owns_normalize` / `owns_parse_line` / `owns_parse_ticket` — parse and normalize owns entries.
  - `owns_entry_overlaps` / `owns_overlaps` — path-overlap predicates (entries and whole lines).
  - `partition_check` — block a candidate ticket against active tickets and open blockers.
  - `ticket_blockers_open` — unresolved `deps:` check.
  - `lease_acquire` / `lease_release` / `lease_list` / `lease_reconcile` — the exclusive-dispatch lease layer over `leases.json`.
  - `partition_drift_check` — after GREEN, record files touched outside the ticket's owns.
  - `partition_suggest` — propose an owns line from a ticket's diff.

### `lib/lifecycle.sh`

Workspace discovery, the review-loop state machine, seat readiness verification, and
selective teardown. Touch it when review rounds, workspace resolution, or `down` flows
change.

- **Consumers:** `herdr-loop-swarm.sh` (status/down/verify), `loop-bot-herd.sh` (review
  directives). Tests: `test_review_loop.sh`, `test_cli.sh`, `test_seat_missing.sh`.
- **Contract:** sourced; directly executable — `lib/lifecycle.sh status | down [flags]
  [dir]`. Eight underscore helpers (not surface).
- **Public functions:**
  - `find_workspace_by_cwd` — resolve the herdr workspace for a directory (never label-based).
  - `review_loop_init` / `review_loop_enabled` / `review_loop_max_rounds` / `review_loop_status` — review-loop configuration and state.
  - `review_loop_findings_path` — where a review round's findings file lives.
  - `review_loop_on_gate_green` — state transition on a green gate; prints machine directives.
  - `review_canonical_sha` — canonicalise a verdict sha once, at the boundary.
  - `review_loop_assign_reviewer` / `review_loop_on_review_verdict` — reviewer routing and verdict processing.
  - `swarm_status` — workspace/seat/profile readout.
  - `lifecycle_confirm` — destructive-step confirmation prompt.
  - `swarm_down` — selective teardown (checkpoint+salvage via worktree.sh; `--keep-workspace`).
  - `seat_wait_ready` / `swarm_verify_seats` — readiness checks the launcher's `verify` runs.

### `lib/layout_engine.sh`

Herdr terminal layout: tab lookup/creation (`herd`, `ops`, `logs`) and 2×2 split-pane
positioning for seats. Touch it only when pane layout changes.

- **Consumers:** `herdr-loop-swarm.sh`. Tests: `test_layout_engine.sh`.
- **Contract:** sourced only.
- **Public functions:**
  - `split_pane` — split a pane (direction, ratio, cwd).
  - `tab_by_label` — find or create a labeled tab in a workspace.
  - `check_and_relocate_geometry` — assert/repair the expected pane arrangement.

### `lib/standby.sh`

The standby orchestrator seat (`looper-standby`) for quota failover: seats a replacement
orchestrator under a mechanics brief and an explicit lock while the primary account is
walled. Touch it when failover behavior changes.

- **Consumers:** `loop-bot-herd.sh`. Tests: `test_standby.sh`.
- **Contract:** sourced; directly executable — `lib/standby.sh status | up [--force] |
  down`. Seven underscore helpers (not surface).
- **Public functions:**
  - `standby_status` — is the standby seated, and who holds the lock.
  - `standby_up` — split pane, start agent, render+deliver brief, take the lock.
  - `standby_down` — close the pane and release the lock.

## Configuration & system foundations

### `lib/config.sh`

Parses `swarm.config.toml` via Python `tomllib` and turns it into safely-quoted shell
exports — the one boundary where config becomes environment. Touch it when config keys or
their validation change.

- **Consumers:** `herdr-loop-swarm.sh`, `loop-bot-herd.sh`, `lib/briefs.sh`,
  `lib/lifecycle.sh`, `lib/providers.sh`, `lib/quota.sh`, `lib/standby.sh`, the
  `lib/cli/stampede-*` wrappers. Tests: `test_config.sh`, `test_cli_init.sh`, `test_quota.sh`.
- **Contract:** sourced; directly executable — `lib/config.sh get <path> | seats | dump |--dump-env
  [slug] | plan |--plan [slug] | markdown [slug] [config]` (default: dump). One underscore helper.
- **Public functions:**
  - `config_get` — read one config value by dotted key (bools render as `true`/`false`).
  - `config_get_seats` — the seat roster with per-seat properties.
  - `config_get_seat_prop` — one property of one seat.
  - `config_project_slug` — the `[swarm] name` slug (ADR 0019).
  - `config_dump_env` — emit the shlex-quoted export block the launcher evals.
  - `config_plan_preview` / `config_plan_markdown` — render the parsed plan for humans (markdown is an alias).

### `lib/profile.sh`

Fail-closed profiling of the target repo: detects `REPO`, `ECOSYSTEM`, `TEST_CMD`,
`DOCS_DIR`, caches them in `profile.env`, and refuses to hand out a non-runnable gate.
Touch it when target-repo detection or gate runnability rules change.

- **Consumers:** `herdr-loop-swarm.sh`, `loop-bot-herd.sh`, `lib/briefs.sh`,
  `lib/pyenv.sh` resolution consumers, `lib/standby.sh`, `lib/gh_sync.sh` (repo slug).
  Tests: `test_profile.sh`.
- **Contract:** sourced; directly executable — `lib/profile.sh detect-repo | detect-test |
  detect-ecosystem | is-runnable | ensure | dump`.
- **Public functions:**
  - `save_profile_var` / `read_profile_var` — profile.env read/write.
  - `detect_repo` / `detect_ecosystem` / `detect_test_cmd` / `detect_docs_dir` — one detection each.
  - `test_cmd_is_runnable` — rejects `""`, `none`, `true` (the synthetic-gate guard).
  - `prompt_test_cmd` — interactive confirmation of a detected suite command.
  - `ensure_profile` — the fail-closed entry: resolve everything or exit non-zero.

### `lib/providers.sh`

Provider abstraction: agent kinds (`claude`, `opencode`, `agy`, `pi`) mapped to binaries,
health probes, fallback chains, model pinning, and the actual agent-start invocations.
Touch it when a provider CLI changes or a kind is added.

- **Consumers:** `herdr-loop-swarm.sh`, `lib/cli/stampede-doctor.sh`,
  `lib/cli/stampede-init.sh`, `lib/cli/stampede-quota.sh`, `lib/cli/stampede-status.sh`.
  Tests: `test_providers.sh`, `test_cli_status.sh`, `test_setup.sh`.
- **Contract:** **sourced only** (no CLI dispatch — the doctor/init/quota CLIs are the entry points).
- **Public functions:**
  - `providers_list_kinds` / `providers_kind_binary` / `providers_kind_remediation` — enumerate and explain kinds.
  - `providers_kind_probe` — is a kind installed and healthy.
  - `providers_resolve_chain` / `providers_healthy_chain` — ordered fallback chains.
  - `providers_check_opencode_models` / `providers_opencode_model_matches` / `providers_opencode_tracked` / `providers_write_opencode_model` — opencode model listing and pinning.
  - `providers_start_agent` — launch one agent in its pane.
  - `providers_seats_from_config` — seat roster with kinds, for planners.

### `lib/setup.py`

The interactive setup assistant behind `stampede setup`: probes local provider
installations, coaches role assignment, writes a clean `swarm.config.toml`. Touch it when
onboarding flow or config authoring changes.

- **Consumers:** `lib/cli/stampede-setup.sh`; compiled by `make lint` (`py_compile`).
  Tests: `test_setup.sh` (via suite), `test_seat_missing.sh`.
- **Contract:** executed — `python3 lib/setup.py <repo> [--non-interactive] [--force]
  [--launcher PATH] [--attention quiet|medium|loud] [--provider ROLE=KIND …]`.
- **Public functions:** `ask`, `parse_assignments`, `probe`, `listed_models`,
  `append_table`, `cost_tier`, `best_listed_model`, `render_config`, `stage`, `main` —
  the wizard's prompt/parse/probe/render pipeline.

### `lib/roles.py`

Canonical seat-role vocabulary (`pm`, `architect`, `looper`, `docs`, `gh`, `reviewer`,
`helper`), normalizing legacy names. Touch it only when roles are added or renamed.

- **Consumers:** `lib/setup.py` (`from roles import seat_role, seat_roles`); compiled by
  `make lint`. Tests: `test_attention.py` (role normalization cases).
- **Contract:** imported (`lib` is on setup.py's path); not a CLI.
- **Public functions:**
  - `seat_role(seat_key, seat_dict)` — one seat's canonical role.
  - `seat_roles(existing_seats)` — `{seat_key: role}` for a whole roster.

### `lib/pyenv.sh`

Resolves a Python 3.11+ interpreter with native `tomllib` — the DOG-1 rule that every
python invocation goes through one resolver with one remedy message. Touch it only when
interpreter floors change.

- **Consumers:** `Makefile`, `herdr-loop-swarm.sh`, `loop-bot-herd.sh`, `lib/common.sh`,
  `lib/config.sh`, `lib/preflight.sh`, the `lib/cli/stampede-*` wrappers. Tests:
  `test_cli.sh`, `test_briefs.sh`, `test_attention.sh`.
- **Contract:** sourced (exports the resolution helpers); directly executable — bare
  `lib/pyenv.sh` prints the resolved interpreter path. Three underscore helpers.
- **Public functions:**
  - `resolve_python` — absolute path to a tomllib-capable python3, or exit 1 with the remedy.

### `lib/preflight.sh`

The 9-point dependency matrix run before launch: herdr, python3, timeout(1), git, gh,
provider runtimes, target-repo sanity. Touch it when dependencies or remedies change.

- **Consumers:** `herdr-loop-swarm.sh`, `lib/cli/stampede-doctor.sh`,
  `lib/cli/stampede-autopilot.sh`, `lib/cli/stampede-init.sh`. Tests: via the doctor suites.
- **Contract:** sourced for its `pf_*` primitives; directly executable —
  `lib/preflight.sh [--quiet] [--json]`.
- **Public functions:**
  - `pf_record` — record one check result (+remedy).
  - `pf_check_herdr` / `pf_check_bin` / `pf_check_python` / `pf_check_timeout` / `pf_check_gh` / `pf_check_agents` / `pf_check_git_repo` — the checks.
  - `preflight_run` — run them all for a target dir.
  - `preflight_exit_code` / `preflight_report_text` / `preflight_report_json` — verdict and reports.

### `lib/common.sh`

Shared utilities everything sources: slugify, session ids, the hermetic gate executor,
timeout resolution, evidence hashing. Touch it rarely and carefully — everything depends on it.

- **Consumers:** sourced by 12 shell entry points (`herdr-loop-swarm.sh`,
  `loop-bot-herd.sh`, and the lib modules). Tests: `test_cli.sh`, `test_gate_hermetic.sh`,
  `test_headless.sh`.
- **Contract:** sourced only. One underscore helper.
- **Public functions:**
  - `slugify` — safe identifier from any string.
  - `telemetry_session_id` — stable per-project session id.
  - `herdr_has_wait_output` — capability probe for herdr read flags.
  - `gate_exec` — run the suite under timeout with the runner's swarm context scrubbed (hermetic, #164).
  - `gate_tree_matches` — HEAD == sha and tree pristine (untracked counts as drift).
  - `resolve_timeout` — find a runnable timeout(1) or say the remedy (DOG-15).
  - `evidence_host` / `evidence_sha256` — receipt material for verdict records.

## Execution, headless & telemetry

### `lib/attention.py`

The looper's attention policy as a durable state machine: which ticket is ready next, which
seats are free, alert throttling, pause/resume, quiet/medium/loud modes. Touch it when
dispatch selection or alert policy changes.

- **Consumers:** `herdr-loop-swarm.sh`, `loop-bot-herd.sh` (frontier drain, next-ticket),
  `lib/cli/stampede-attention.sh`, `lib/cli/stampede-autopilot.sh`. Tests:
  `test_attention.py`, `test_attention.sh`, `test_autopilot.sh`.
- **Contract:** executed — `python3 lib/attention.py mode|event|resume|next <repo> [values…]`
  (`next` accepts only `auto`). State lives in `<repo>/.herdr-swarm/attention.json`.
  Thirteen private methods (not surface).
- **Public surface:** class `Attention(repo)` — `mode`, `set_mode`, `is_paused`, `resume`,
  `seat_ready`, `seat_has_outstanding_work`, `profile_value`, `github_repo`, `gate_ready`,
  `issue`, `issue_ready`, `list_issues`, `map_body`, `map_tickets`, `local_ticket_path`,
  `local_ticket_status`, `local_ticket_ready`, `next_ready_ticket`, `dispatch`, `repair`,
  `ask`, `event`.

### `lib/headless.sh`

Subprocess harness for unattended batches: spawn workers with timeouts, reap exits, count
attempts, dead-letter with reasons, drain-and-release on completion (ADR 0015/0016).
Touch it when batch execution or dead-letter policy changes.

- **Consumers:** `loop-bot-herd.sh` (headless-mode seams), `lib/cli/stampede-headless.sh`.
  Tests: `test_headless.sh`, `test_async_gate.sh`, `test_cli.sh`.
- **Contract:** sourced (its functions drive the batch loop); no CLI of its own — the
  wrapper is the entry. One underscore helper.
- **Public functions:**
  - `headless_spawn` — spawn a worker subprocess for a ticket (pidfile + log).
  - `headless_status` / `headless_kill` / `headless_reap` — lifecycle of one worker.
  - `headless_attempt_count` — a ticket's conclusive-failure count from the session log.
  - `headless_deadletter_due` / `dead_letter_record` / `headless_deadletter_count` — the dead-letter queue.
  - `headless_drain_and_release` — enqueue, drain, release the lease for a finished ticket.

### `lib/briefs.sh`

Renders `briefs/*.in.md` templates into `.herdr-swarm/briefs/` with per-project variables,
and delivers briefs by file path with a nonce acknowledgement. Touch it when briefs or
their delivery protocol change.

- **Consumers:** `herdr-loop-swarm.sh` (at `up`), `lib/standby.sh` (failover brief).
  Tests: `test_briefs.sh`.
- **Contract:** sourced; directly executable — `lib/briefs.sh render <dir> <slug> | deliver
  <seat> <brief>`. Exports `ARBITER_BIN` so templates name the governing arbiter (DOG-13).
  One underscore helper.
- **Public functions:**
  - `substitute_template` — argv-safe template substitution (values never become Python source).
  - `render_all_briefs` — render the full set for a target dir + slug.
  - `deliver_brief_nonce` — prompt a seat with the brief path until it acknowledges the nonce.

### `lib/telemetry.py`

Local-only event log: structured JSONL under `.herdr-swarm/traces/` plus the live ANSI
stream the Ops pane shows. Zero network — nothing leaves the machine. Touch it when event
shapes or the stream display change.

- **Consumers:** `herdr-loop-swarm.sh`, `loop-bot-herd.sh`, `lib/arbiter.sh`,
  `lib/cli/stampede-quota.sh`; compiled by `make lint`. Tests: `test_telemetry.sh`.
- **Contract:** executed — `python3 lib/telemetry.py log <session> <event> <agent>
  <ticket> '<json>' --trace-dir <dir> | stream <session> <trace-dir>`. Four private
  helpers (not surface).
- **Public functions:**
  - `resolve_trace_dir` — pin the trace directory for a session.
  - `log_event` — append one JSONL event.
  - `badge_for` / `format_event` — stream display formatting.
  - `stream` — the live follow loop.

### `lib/quota.sh`

Point-in-time quota probing for shared provider accounts and the dispatch gate that defers
work while a wall is observably up (positive signals only — no signal never pauses
anything). Touch it when quota semantics change.

- **Consumers:** `loop-bot-herd.sh`, `lib/standby.sh`, `lib/cli/stampede-quota.sh`.
  Tests: `test_quota.sh`, `test_standby.sh`.
- **Contract:** sourced; directly executable — `lib/quota.sh agy <seat> | gate <kind>
  <seat> | wait <target-dir>`. Two underscore helpers.
- **Public functions:**
  - `quota_probe_kind` — probe one seat's kind (`ok:<n>s`, `unknown`, errors).
  - `quota_probe_openrouter` — credits probe through the optional proxy credentials.
  - `quota_wait_banner` — block until a banner's countdown passes.
  - `quota_gate` — the dispatch gate with first-sight registration of banners.

### `lib/gh_sync.sh`

Two-way reconciler between local Wayfinder tickets (`maps/tickets/*.md`) and GitHub issues:
plans creates/closes/updates, applies only under `--apply`. Touch it when ticket↔issue
sync rules change.

- **Consumers:** human-run directly (no runtime consumer); sources `lib/profile.sh` for
  the repo slug. Tests: `test_gh_sync.sh` (fake `gh`), `test_repo_state.sh`.
- **Contract:** executed — `lib/gh_sync.sh [--dry-run] [--apply|--sync] [--repo OWNER/REPO]
  [--target-dir DIR] [--direction push|pull|both] [--ticket ID_OR_FILE] [--json]`
  (default: dry-run).
- **Public surface:** `show_help`; the reconciliation engine is the script's `main` flow
  (not function surface).

## CLI command modules (`lib/cli/`)

All eleven are convention-dispatched by `bin/stampede`: the file sources, the function
`stampede_cmd_<command>` (dashes folded to underscores) runs with the remaining
arguments. Each wrapper is deliberately thin — policy lives in the module beneath it.

### `lib/cli/stampede-arbiter.sh`
- **Command:** `stampede arbiter [dir] <subcommand> [args…]`
- **Purpose:** human wrapper on `lib/arbiter.sh` — `drain`, `promote`, `enqueue`,
  `pr-body`, enforcing execution against the right target repo.
- **Public function:** `stampede_cmd_arbiter`.

### `lib/cli/stampede-attention.sh`
- **Command:** `stampede attention [dir] [mode|event|resume|next …]`
- **Purpose:** front-end for reading and steering the attention policy state.
- **Public function:** `stampede_cmd_attention`.

### `lib/cli/stampede-autopilot.sh`
- **Command:** `stampede autopilot [dir] on|off|status`
- **Purpose:** compose existing switches into fast local integration — quiet attention,
  deterministic intake, per-pass drains, a TTL'd promote grant; `off` restores.
- **Public function:** `stampede_cmd_autopilot`.

### `lib/cli/stampede-doctor.sh`
- **Command:** `stampede doctor [dir]`
- **Purpose:** run preflight + provider checks + herdr daemon inspection and print
  actionable remedies.
- **Public function:** `stampede_cmd_doctor`.

### `lib/cli/stampede-headless.sh`
- **Command:** `stampede headless [dir] [--max-tickets N] [--timeout M]`
- **Purpose:** the unattended batch: dispatch→gate→enqueue per backlog ticket, no panes;
  dead-letters failures and exits non-zero on them.
- **Public function:** `stampede_cmd_headless`.

### `lib/cli/stampede-init.sh`
- **Command:** `stampede init [dir] [--force] [--preset name]`
- **Purpose:** generate a valid project-local `swarm.config.toml` from detected runtimes
  and presets.
- **Public function:** `stampede_cmd_init`.

### `lib/cli/stampede-quota.sh`
- **Command:** `stampede quota [dir] [--json]`
- **Purpose:** print provider account headroom across configured backends. One underscore
  helper.
- **Public function:** `stampede_cmd_quota`.

### `lib/cli/stampede-setup.sh`
- **Command:** `stampede setup [dir] [args…]`
- **Purpose:** run `lib/setup.py`'s guided wizard against a target repo.
- **Public function:** `stampede_cmd_setup`.

### `lib/cli/stampede-status.sh`
- **Command:** `stampede status --rich [dir] [--json]`
- **Purpose:** the session trust dashboard — activity, event counters, worker states,
  trust-tax — read from traces. Five underscore helpers.
- **Public function:** `stampede_cmd_status`.

### `lib/cli/stampede-version.sh`
- **Command:** `stampede version [--check]`
- **Purpose:** print the version, verify VERSION ↔ CHANGELOG ↔ tags alignment (PUB-5).
- **Public function:** `stampede_cmd_version`.

### `lib/cli/stampede-worktree.sh`
- **Command:** `stampede worktree [dir] [--apply] [--force] [--base <ref>]`
- **Purpose:** audit and safely prune registered worktrees; dispatches to
  `scripts/worktree-sweep.sh`.
- **Public function:** `stampede_cmd_worktree`.
