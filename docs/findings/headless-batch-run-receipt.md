# Headless batch run receipt — PROVE-HEADLESS-1

**Date:** 2026-09-30 · **Runner:** arch-2 seat · **Target:** ephemeral scratch repo under `/tmp`
**What this is:** `bin/stampede headless` run for real against live queued work — real `opencode run`
subprocesses, real suite gates, real harvest — plus a deliberate exercise of the HEADLESS-5 safety
machinery. Seven batch attempts, two targeted harness probes, and two operator-side recovery steps,
all quoted below. **Eight findings; three of them are genuine defects** in shipped code paths. Per
this ticket's Notes, a found defect is a successful outcome — nothing here was worked around silently;
every workaround used is named as such.

## Setup

Scratch repo `/tmp/headless-batch-prove`: `git init -b main`, fake never-contacted remote
(`https://github.com/headless-batch/scratch.git`), `Makefile` (`test:` → `sh ./check.sh` — a real gate
that can and does fail), three self-contained backlog tickets with the completion protocol spelled
out inline (`ARCH DONE #<id> <sha>`), and `.gitignore` for `.herdr-swarm/` (untracked files count as
tree drift in `gate_tree_matches`).

`herdr` deliberately off `PATH` (it lives in `/opt/homebrew/bin` on this machine, so a staging dir
symlinked only the needed binaries):

```
$ env PATH=/tmp/headless-batch-prove-bin:/usr/bin:/bin:/usr/sbin:/sbin bash -c 'command -v herdr'
(unchecked exit 1 — not found)
opencode ok -> /tmp/headless-batch-prove-bin/opencode
git ok -> /tmp/headless-batch-probe.../bin/git      (symlinks into /opt/homebrew/bin)
jq/python3/timeout/make/bash/seq/sleep ok
python3 -c "import tomllib" -> tomllib ok
```

## Run ledger (all times 2026-09-30, local)

| # | Window | Elapsed | Outcome |
|---|---|---|---|
| 1 | 10:48:46→10:48:54 | 8s | 3× instant worker death (F1) → **3 dead letters, exit 1** |
| 2 | 10:52:27→10:52:29 | 2s | phantom worktree (F3) → all tickets parked, **exit 0 no-op** |
| 3 | 10:54:11→10:54:19 | 8s | bad opencode permission schema (setup error, my own) → 3 DL, exit 1 |
| 4 | 10:54:57→10:55:27 | 30s | `external_directory` auto-reject (F4) → 3 DL, exit 1 |
| 5 | 10:58:48→10:59:24 | 36s | **happy path proven end-to-end** (T10 green); T20/T30 parked (lease, by design); exit 0 |
| 6 | 11:00:53→11:08:26 | 7m33s | designed-RED ticket: real gate RED, ceiling not reached (F6/F7), exit 0 |
| 7 | 11:10:00→11:13:24 | 3m24s | env-override attempt clobbered (F7) → same shape as 6, exit 0 |
| — | 11:00:30→11:00:37 | 7s | operator recovery: `lib/arbiter.sh drain` → integrated; `loop-bot-herd.sh once` → lease released |
| — | after | ~40s | harness probes: wall clock kills TERM-accepting worker; TERM-ignoring worker evades it (F8) |

## The proven pipeline (attempt 5, verbatim)

Dispatch, harvest, gate, enqueue — every stage real:

```
$ bin/stampede headless /tmp/headless-batch-prove --max-tickets 3
headless: /tmp/headless-batch-prove — 3 dispatchable ticket(s), cap 3, budget 1800s, worker arch-1-headless-batch-scratch (opencode)
headless: dispatching #T10 → arch-1-headless-batch-scratch (brief: .../maps/tickets/10-notes-entry.md, worktree: .../worktrees/arch_1)
headless: #T20 parked — partition overlap
headless: #T30 parked — partition overlap
headless: batch done — 1 dispatched, 0 dead-letter record(s) this session
exit code: 0
```

Real subprocess work (worker log, `logs/arch-1-headless-batch-scratch.log`):

```
$ git commit -am "T10: notes entry" && git rev-parse HEAD && git status
[swarm/headless-batch-scratch/arch_1 e740fa4] T10: notes entry
 1 file changed, 1 insertion(+)
e740fa4a70e6f3e67a668bc552d1d0f515f36576
ARCH DONE #T10 e740fa4a70e6f3e67a668bc552d1d0f515f36576
```

Real deliverable: `git show e740fa4` → `NOTES.md | 1 +` … `+2026-09-30: headless batch proven`.

Real harvest + real suite gate + real enqueue (`.herdr-swarm/`):

```
session-verdicts.jsonl:
{"ts": 1790791163, "ticket": "T10", "sha": "e740fa4…", "seat": "arch-1-headless-batch-scratch", "suite": "green", "exit_code": 0, …}
gate-logs/arch-1-headless-batch-scratch-e740fa4.log:  gate: green
integration.jsonl: {"ticket":"T10", … "status":"queued"}
```

Partition/lease held exactly per DOG-16/ADR 0012 (green does not release; T20/T30 parked).

Integration itself does **not** happen inside the batch (F5) — the operator completed it, herdr still
off PATH:

```
$ lib/arbiter.sh drain            →  arbiter: #T10 integrated @ e740fa4 (was eaac483)
queue: T10 status "integrated", merge_sha e740fa4…
refs: main eaac483 (untouched) · swarm/…/integration e740fa4
$ loop-bot-herd.sh once           →  ✓ lease released: #T10 integrated — paths re-open for dispatch
leases.json: {"version":1,"leases":[]}
```

## Safety mechanisms (HEADLESS-5) — what actually fired

**DEAD_LETTER + non-zero exit: fired for real (attempt 1)** — three workers died instantly (root
cause F1 below), each ticket dead-lettered with lease release, batch exited 1:

```
headless: #T10 did not conclude within the batch budget — dead-lettering
headless: batch done — 3 dispatched, 3 dead-letter record(s) this session
headless: DEAD LETTERS present — see /tmp/headless-batch-prove/.herdr-swarm/dead-letter.jsonl
exit code: 1
dead-letter.jsonl: {"ts":1790790528,…,"ticket":"T10","sha":"3d763b5","reason":"batch wall clock exhausted before a verdict"}
```

**Re-verdict ceiling (`max_verdict_attempts` → DEAD_LETTER): could not fire — structurally
unreachable (F6).** Attempt 6 built exactly the ticket the mechanism describes (a deliverable the gate
rejects). The gate caught it for real — `gate: slow-mirror.txt present (timeout-trap deliverable)` /
`make: *** [test] Error 1`, session record `"suite": "RED", "exit_code": 2` — but one conclusive
failure is below the ceiling of 2, and the critique turn that would produce attempt 2 is killed the
moment the first record concludes the ticket. Attempt 7 tried to lower the ceiling via env and
couldn't (F7).

**Subprocess timeout eviction: bound honored, but evadable (F8).** Probe (direct harness, stub CLIs):

```
TERM-accepting stub, 3s wall clock:   status: exited rc=124          ✓ killed at the bound
TERM-IGNORING stub, 3s wall clock:    status after 6s: running (pid 31552)   ✗ evaded
                                      status after 32s: exited rc=124 (its own sleep 30 ending)
```

## Findings

1. **Stale global default model kills bare-repo workers instantly** (environmental, high impact for
   first-run users). The machine's `~/.config/opencode/opencode.json` pins `zai-coding-plan/glm-4.6`,
   which the provider no longer offers. Any target repo without project-level opencode config falls
   back to it; the worker dies in ~2s with `ProviderModelNotFoundError` visible only in
   `logs/<seat>.log`, never in batch output. Fix used here: pin a valid model in the target repo's
   `.opencode/opencode.json`. Worth a docs note in the headless design doc at minimum.
2. **The unconcluded-path dead-letter reason is wrong and hides the cause.** Any worker that dies
   without a verdict — provider error, invalid config, permission rejection — is recorded as
   `"batch wall clock exhausted before a verdict"` (lib/cli/stampede-headless.sh:220-222). Nothing in
   batch output points at `logs/<seat>.log`, where the real error sits. A reason like
   `worker exited rc=1 without a verdict` plus a log pointer would make attempt 1 self-diagnosing.
3. **`worktree_provision` can report success for a worktree that does not exist** (defect).
   `_wt_add_with_retry` returns 1 and prints the real error, but `worktree_provision` ignores its rc
   (lib/worktree.sh:151) and prints the success shape anyway. Inside the headless call site
   `if ! prov=$(worktree_provision …)` (lib/cli/stampede-headless.sh:115) `set -e` is suspended, so
   the failure propagates nowhere. Repro: leave a *locked, missing* worktree entry + its branch from a
   prior run (e.g. state dir deleted between runs), re-run `headless`:
   ```
   headless: dispatching #T10 → … (worktree: …/worktrees/arch_1)
   lib/headless.sh: line 70: cd: …/worktrees/arch_1: No such file or directory
   headless: worktree dir not found:            ← empty path in the message (cd failed inside $())
   headless: #T10 spawn failed — parking  … batch done — 0 dispatched, 0 dead-letter record(s)  exit 0
   ```
   A fully green-looking no-op. Also note the CLI form *does* fail loudly (`bash lib/worktree.sh
   provision …` exits 1) — but only by accident of top-level `set -e`. Fix: check the retry's rc and
   `return 1` (with its own test); separately, `headless_spawn`'s `wt=$(cd "$wt" && pwd)` should guard
   the cd so the error names the missing path.
4. **The dispatch protocol points workers at a path their sandbox forbids.** Briefs live in the root
   checkout; the worker's cwd is the worktree — an *external directory* to opencode, which
   auto-rejects in run mode:
   ```
   ! permission requested: external_directory (/tmp/headless-batch-prove/maps/tickets/*); auto-rejecting
   ✗ Read /tmp/headless-batch-prove/maps/tickets/30-slow-deliverable.md failed
   Error: The user rejected permission to use this specific tool call.
   ```
   Today a headless target repo *must* ship `permission.external_directory: "allow"` in its project
   config or every worker dies unread. Either the design doc must say so loudly, or the harness should
   copy the brief into the worktree before spawning.
5. **The batch never drains and never releases leases** (design gap, same smell PROVE-4 fixed for the
   supervisor loop). Greens sit `queued` in `integration.jsonl`; leases stay held; a no-owns ticket
   therefore holds the whole repo forever. In attempt 5, one green ticket parked the other two
   permanently — a second batch run would park all three. Nothing inside headless runs
   `arbiter_auto_drain` or `lease_release_integrated` (both live in `cmd_once`, which the batch never
   calls). Recovery is operator-side and works herdr-less (demonstrated above), but the "unattended
   batch" currently self-wedges after its first green no-owns ticket.
6. **A first-RED ticket ends the batch exit 0, and the ceiling is unreachable in-batch** (defect vs
   documented contract). The per-ticket wait treats *any* session record as "concluded" — including
   `RED` — then `headless_kill`s the just-spawned critique turn. With `max_verdict_attempts = 2`,
   attempt 2 can never happen inside one run (the re-verdict worker is killed), and across runs the
   held lease parks the ticket (F5). Net: the designed "RED ×N → DEAD_LETTER" transition is
   unreachable in practice; the only producing path is worker-death-without-verdict (attempt 1). Exit
   0 with a RED, un-integrated ticket in the log is at best misleading for CI.
7. **The headless knobs have no env override — the TOML binding silently clobbers them**
   (defect vs the documented `gate_concurrency` hierarchy). `config_dump_env` unconditionally emits
   `CONFIG_HEADLESS_MAX_ATTEMPTS` / `CONFIG_HEADLESS_WORKER_TIMEOUT_S` from `swarm.config.toml`
   (lib/config.sh:151-158) when the supervisor is sourced, so `CONFIG_HEADLESS_WORKER_TIMEOUT_S=120
   bin/stampede headless …` silently runs with the TOML's 600 (attempt 6) and
   `CONFIG_HEADLESS_MAX_ATTEMPTS=1 …` silently runs with 2 (attempt 7). Either honor env (emit only
   when unset) or document that per-run tuning requires a TOML, and fail loudly on unknown env
   overrides.
8. **The worker wall clock is TERM-only.** `"$TIMEOUT_BIN" "$tmo" opencode …` (lib/headless.sh:136-138)
   never escalates past SIGTERM; GNU `timeout` without `--kill-after` waits forever on a child that
   ignores it (probe 2 above). The DOG-15-style comment says "hard wall-clock bound"; make it true
   with `-k <grace>` (or `timeout -s KILL`), keeping the rc=124 semantics.

## What worked, for the record

Profile fail-closed re-resolved cleanly on every attempt; worktree provisioning fresh-run; nonce
channel replies (the worker wrote its channel file and printed only the path, per protocol); anchored
verdict harvest from a scraped log; async gate jobs on the isolated worktree; the partition/lease
guard; the arbiter's CAS drain; the once-pass lease release — all with `herdr` absent from PATH
throughout. `main` was never touched by anything.

## Suggested follow-ups (ticket-sized)

- F3: `worktree_provision` rc propagation + phantom-path guard in `headless_spawn` (defect, tests).
- F5/F6: headless batch should drain + release leases per ticket (or at batch end) and treat RED as
  non-concluded until the ceiling actually decides — likely one design ticket covering both.
- F7: env-override hierarchy for the headless knobs (match `gate_concurrency` semantics).
- F8: `timeout -k` hardening in `lib/headless.sh`.
- F2/F4: honest dead-letter reasons with log pointers; brief-into-worktree delivery or a loud
  config requirement in the design doc.
