# Stampede ponytail audit — 2026-11-08 (AUDIT-1)

**Date:** 2026-11-08 · **Author:** `arch-2-stampede` · **Scope:** whole production surface at
HEAD `4901397` — `bin/stampede`, `herdr-loop-swarm.sh`, `loop-bot-herd.sh`, all `lib/*.sh`,
`lib/*.py`, `lib/cli/*.sh`, `Makefile`, `scripts/`, plus test-suite health · **Status:** report
only; changes nothing (research dispatch).

**Method:** six parallel slice audits (supervisor; arbiter+partition; launcher+config chain;
lifecycle/headless/standby/worktree/quota; briefs/telemetry/attention/gh_sync/CLIs;
Makefile/scripts/tests), each reading its slice end to end. The seat owner then re-verified
every numbered receipt below against the cited lines and re-ran the probe-based ones in
scratch repos. 53 weaker candidates were dropped at the concrete-case bar (per slice: 9, 12,
10, 12, 5, 5) — they are not findings. Suites at HEAD: 34 green (`make test`, 4m21s).

**Load assumed:** one human operator, one herd of ~5 agent seats on one machine, supervisor
poll every ~30s, suite gate `make test` per verdict. This is a local orchestration tool, not a
multi-tenant service; "scale" means the poll loop, the gate queue and unbounded state files.

## Relationship to the 2026-10-09 audit

- **Findings 6–8 of the 2026-10-09 report remain void** — permanently lost, per its §4. This
  report's numbering is independent of them; nothing here renumbers into that gap.
- 2026-10-09 findings 1–5 and 9 are verified still fixed (covered by today's green suites);
  overlaps with that report are cross-referenced **by class** (finding 2 below is the same
  class as its finding 5, the brief-renderer injection).
- Its unnumbered open thread — rendered briefs go stale until the next `up` — is **still
  open**: `render_all_briefs` runs only on the `up` path (`herdr-loop-swarm.sh:501`) and on
  the manual `briefs render` CLI (`lib/briefs.sh:224`). Not re-numbered; unchanged, not worse.
- The postmortem's §11 decisions (2026-11-07) were read first and are **not** re-litigated:
  one slug (ADR 0019), the 2026-11-06 discards stay discarded, no `stampede reset`,
  promote/push stay human acts. Postmortem arbiter fixes #165–#173 all landed and are not
  re-filed. `ARB-TREE-CACHE-1` is re-raised below as a triaged finding only (deferred item
  D29): its own refile condition — "after the arbiter fixes" — is now met.
- Findings 6, 7 and 8 and deferred items D6–D9 carry over from the PR #183 ponytail review
  (2026-11-08, same seat), re-verified at HEAD.

## What this repo does

Stampede seats a herd of LLM agents in Herdr terminal panes against any target repo, gates
their verdicts by running the target's test suite in a worktree, queues green work for an
arbiter that integrates and (only with a human act) promotes it, and watches leases, quota,
credits and review state along the way. The load is one operator and a handful of seats.

---

## Must fix

1. **`gh_sync --direction pull` still writes to GitHub** (`lib/gh_sync.sh:351-361`, `:413-420`, `:363`)
   - **What this is:** Ticket↔issue reconciliation takes `--direction push|pull|both`, but
     `direction` is consulted in exactly one branch (`:363`).
   - **Problem:** With `--direction pull --apply`, a locally resolved ticket linked to an open
     issue plans `UPDATE_REMOTE close` unconditionally, and any unlinked local ticket plans
     `CREATE` unconditionally — pull mode closes issues and creates new ones, the opposite of
     what the flag promises. Only the printed plan betrays it.
   - **Fix:** Gate the close subaction (`:351`) and Case-2 CREATE (`:413`) on
     `direction in ("push", "both")`; emit a skip line in pull mode instead.
   - **If we skip it:** The next "safe pull" mutates the remote and erodes trust in every
     dry-run/apply promise the tool makes.

2. **Two Python-source interpolation sites survive the injection fix** (`lib/config.sh:49`, `lib/briefs.sh:107-115`)
   - **What this is:** The repo rule (CLAUDE.md, and 2026-10-09 finding 5's fix) is that values
     travel as `sys.argv`, never interpolated into Python source.
   - **Problem:** `config_get` embeds the key path into the program text
     (`keys = '$key_path'.split('.')`) and `vars_json` embeds `'$slug'`. A config key like
     `x' + __import__('os').system('…') + 'y` executes when `config_get` runs — probe-verified
     ("INJECTION EXECUTED"). Configs live in target repos where agent seats can edit them;
     a slug with an apostrophe breaks brief rendering the same way. Same class as 2026-10-09
     finding 5, two sites missed by that fix.
   - **Fix:** Pass key path and slug as argv/environment, matching `_py_read`'s existing
     signature; one quote-bearing test each.
   - **If we skip it:** The argv-only invariant exists only where it was last patched, and any
     agent-editable config value is a code-exec vector.

3. **Standby takeover takes the orchestrator lock with no brief** (`lib/standby.sh:186`, contrast `:172-184`)
   - **What this is:** When the looper is quota-walled, standby `up` seats a replacement
     orchestrator and hands it the mechanics brief.
   - **Problem:** `deliver_brief_nonce … || true` swallows an honest delivery failure, then
     the lock is written and success is reported — a briefless zombie holds the orchestrator
     lock while the real looper is still walled. A re-run no-ops ("already holding the lock",
     `:140-143`), so delivery cannot even be retried without `down`.
   - **Fix:** On delivery failure, close the pane and `return 1` before the lock write — the
     same shape as the two guards directly above it.
   - **If we skip it:** The failover path can wedge the whole herd behind a lock held by an
     agent that never received its instructions.

4. **An old integration row frees every future lease for its ticket** (`loop-bot-herd.sh:1276-1290`, acquire at `:1261`)
   - **What this is:** `lease_release_integrated` releases a ticket's lease when
     `integration.jsonl` shows it `integrated|promoted`. The log is append-only and the check
     has no time bound.
   - **Problem:** Re-dispatch after an integration is the designed flow (the release pass's
     own "paths re-open" message). Ticket T integrates once → looper re-briefs T → a fresh
     lease is acquired (`:1261`) → the next pass matches the *old* row and releases the new
     lease while the worker is mid-ticket → a second overlapping dispatch is now allowed,
     silently defeating the disjoint-ownership invariant (DOG-16).
   - **Fix:** Only release on rows with `ts` at or after the lease's `acquired_at` epoch, or
     record the integration-row count in the lease at acquire time.
   - **If we skip it:** Every re-opened ticket loses its exclusivity after one pass — two
     workers editing the same paths is exactly what partitions exist to prevent.

5. **`promote --pr` breaks outside the repo root and has zero happy-path tests** (`lib/arbiter.sh:680-689`; only refusal tested at `tests/test_arbiter.sh:346-348`)
   - **What this is:** The only code in the product that pushes to a remote: `git push` (cwd-
     correct) followed by bare `gh pr create` / `gh pr view`, which resolve the repo from
     `$PWD` — and the CLI wrapper exists precisely so you can run it from elsewhere (#170).
   - **Problem:** `stampede arbiter <dir> promote --pr --confirm` from any other directory
     pushes the integration branch, then `gh` fails — a human-gated act half-completes:
     pushed, no PR, no `promoted_to: "pr"` record. No suite ever exercises a successful
     `--pr` promote, so arg drift or a broken invocation ships green.
   - **Fix:** Wrap both gh calls in `(cd "$ARB_REPO" && gh …)`; add one scenario with a
     scratch bare `origin` and a `gh` stub asserting argv, remote movement, and the record.
   - **If we skip it:** The first real PR promote run from a pane cwd fails mid-act, leaving
     a pushed branch and no record.

6. **The sweep's SAFE prune destroys ignored files** (`scripts/worktree-sweep.sh:230-250` vs `:311-314`) — carried from the PR #183 review
   - **What this is:** The audit's dirty check uses `git status`-style probes, which do not
     count git-ignored files.
   - **Problem:** A merged worktree holding only ignored content (`.env.local`,
     `node_modules/`) reads clean, is labeled `[SAFE]`, and `--apply` deletes it with the
     contents — probe-verified. The `--force` path refuses to touch ignored files at all
     (`:311-314`): the careful mode protects exactly what the bulk mode destroys.
   - **Fix:** Fold the ignored-file probe from `:311` into the dirty classification so
     ignored content marks a worktree `[DIRTY]` (preserved without `--force`); add the probe
     as a regression test.
   - **If we skip it:** Bulk cleanup of old worktrees — the tool's main use — silently deletes
     local secrets and caches.

7. **The sweep's seat-ledger read fails open** (`scripts/worktree-sweep.sh:158-162`) — carried from the PR #183 review
   - **What this is:** Live seats are found by jq-reading `.herdr-swarm/seats.json`;
     `2>/dev/null || true` swallows a missing jq or corrupt JSON.
   - **Problem:** An unreadable ledger yields an empty seat list, and a freshly seated worker
     — clean, on a base-equal branch — classifies as `[SAFE]`, the exact case the guard exists
     for (`:155-156`). `--apply` then removes the live seat's worktree.
   - **Fix:** If `seats.json` exists but the read *errors* (distinct from a valid empty
     roster), `die` — fail closed.
   - **If we skip it:** One corrupt ledger file plus one sweep deletes a live worker's tree.

## Should fix

8. **A timeout is "environment" for the base but "RED" for the worker** (`loop-bot-herd.sh:383-387` vs `:460-473`; default timeout 300s at `:43`) — carried from the PR #183 review
   - **What this is:** PR #183 made a base-suite timeout (rc 124/128+) non-attributing and
     dropped its cache so the next call re-measures.
   - **Problem:** The worker's own gate rc of 124/128+ still lands in the plain RED branch:
     the worker is told to fix an environment problem, and every re-verdict re-runs the base
     suite — up to 300s each, synchronously inside one supervisor poll (`cmd_once`,
     `:1416-1440`). An environment-wide timeout (the load spike that motivated #183) becomes
     worker repair churn plus multi-minute poll stalls, instead of one human notification.
   - **Fix:** Symmetry — treat a worker gate rc of 124/128+ as non-attributing too (own suite
     value, human notice, no repair feedback), or add a time-stamped negative cache for base
     timeouts so one stuck base re-measures at most every N minutes.
   - **If we skip it:** The next load spike produces false repair loops and blocked polls.

9. **`isolated: 1` seats silently skip the pre-dispatch fast-forward** (`loop-bot-herd.sh:1303` vs the SUPER-1 normalization at `:264-269`)
   - **What this is:** `dispatch_sync_worker` string-compares the ledger's `isolated` field to
     `true`; SUPER-1 established the ledger also carries integer `1` (jq prints `1`), and
     `resolve_seat_gate`/`gate_spawn`/`gate_reap` all normalize both forms.
   - **Problem:** A ledger with `"isolated": 1` (older launcher output, still on disk) makes
     the fast-forward sync to `swarm/<slug>/integration` a silent no-op — the worker forks
     from a stale base, exactly what the sync exists to prevent.
   - **Fix:** Use `resolve_seat_gate "$worker"` and test `$GATE_ISOLATED == true` (deletes the
     special-casing rather than adding a fourth copy of the rule).
   - **If we skip it:** Old ledgers quietly lose base sync; the bug class SUPER-1 closed
     re-enters through a fourth consumer.

10. **The harvest window keeps only five verdicts** (`loop-bot-herd.sh:778`, `:1089`)
    - **What this is:** Both harvest loops take only the last 5 *matching* lines of a seat's
      pane output; the window never moves backward.
    - **Problem:** With the supervisor paused or down while 6+ verdicts accumulate (a repair
      loop, or a reviewer clearing a queue), the 6th-oldest anchor is unreachable on every
      later pass — not deferred, lost: a ticket can sit `awaiting_review` forever with no
      alert. The dedupe machinery that makes full re-scans safe already exists.
    - **Fix:** Mirror the review lane's seen-file (exact-line key) for ARCH DONE lines and
      drop the tail; old lines then cost a string compare per pass.
    - **If we skip it:** Verdicts silently vanish during any pause longer than a burst.

11. **A recycled pid adopts a dead gate job forever** (`loop-bot-herd.sh:486-497`; job records already carry `start_time` at `:328`)
    - **What this is:** `gate_recover` discards rc-less jobs only when `kill -0` says the pid
      is dead; a live pid is "adopted as-is", silently.
    - **Problem:** After a reboot or long downtime the recorded pid is routinely an unrelated
      process — the job looks alive forever, its verdict `continue`s at every harvest
      (`gate_job_running`), and two such jobs permanently exhaust `GATE_CONCURRENCY`: every
      new verdict hits "gate slots full" with nothing running.
    - **Fix:** Also discard rc-less jobs whose `start_time` is older than `SUITE_TIMEOUT_S` +
      slack — the wall clock is the real bound; pid liveness cannot survive pid reuse.
    - **If we skip it:** One reboot can wedge the gate pipeline until a human deletes job
      files by hand.

12. **A failed worker prompt leaks the dispatch lease** (`loop-bot-herd.sh:1261`, `:1332`)
    - **What this is:** `cmd_dispatch` acquires the lease in the partition guard, then prompts
      the seat via herdr.
    - **Problem:** If `herdr agent prompt` fails (seat momentarily absent), `set -e` exits
      with the lease still held — the ticket is blocked on every future dispatch
      ("BLOCKED (lease)") until a human runs `lease release`. The sync-refusal path directly
      above (`:1321-1322`) got exactly this guard; the prompt path did not.
    - **Fix:** `herdr agent prompt … || { lease_release "$tname"; bad "…prompt failed — lease
      released"; exit 1; }`.
    - **If we skip it:** Any transient herdr failure converts into a permanently blocked
      ticket.

13. **A crash mid-base-gate permanently disables base attribution for that base** (`loop-bot-herd.sh:369-376`)
    - **What this is:** `_base_is_red` creates a scratch worktree, runs the suite, writes the
      rc cache.
    - **Problem:** A crash between `worktree add` and the rc write (Ctrl-C on `once`, laptop
      sleep) leaves the `wt-<base12>` directory behind without an rc; every later call
      re-enters the `[[ ! -f rcf ]]` branch, the add fails (path exists), and the function
      returns "not base red" forever — every RED on that base is attributed to the worker,
      and headless mode walks tickets to DEAD_LETTER for a base defect.
    - **Fix:** On add failure, `worktree remove --force` (or `rm -rf`) the stale path and
      retry the add once.
    - **If we skip it:** One interrupted base gate poisons attribution for that base until a
      human cleans `base-gates/` by hand.

14. **The headless ceiling counts a ticket's whole history** (`loop-bot-herd.sh:908-916`; `lib/headless.sh:246-251`)
    - **What this is:** `headless_attempt_count` scans the never-rotated session log for all
      RED/invalidated/stale rows the ticket has *ever* produced; HL-DL-1 fixed exactly this
      staleness for dead-letter counting with a since-index, but not here.
    - **Problem:** A ticket that dead-lettered at 2 attempts, was resolved by a human and
      re-briefed, dead-letters again on its first legitimate RED (count 3 ≥ 2) with zero
      critique turns — the ceiling stops only the first runaway, never a retry.
    - **Fix:** Count only records at or after the current lease's `acquired_at` epoch
      (`leases.json` already stores it).
    - **If we skip it:** Headless retries behave as if pre-condemned; the "stop the runaway
      loop" guarantee applies once per ticket, ever.

15. **Two holes in the partition lease layer** (`lib/partition.sh:296-306`, `:233-234`)
    - **What this is:** The module's own header rule (`:16-17`) — a ticket without `owns`
      owns everything — and the exclusive lease both treat no-owns as whole-repo.
    - **Problem:** (a) `_partition_active_conflicts` skips the overlap test when the *active*
      ticket has no owns, so an owns-ful candidate sails past an in-progress whole-repo
      ticket (probe-verified) the moment its lease is gone — a lease flap re-opens the exact
      double-edit hazard. (b) `_lease_lock` reaps a stale lock with a bare `rm -rf`, so two
      waiters can interleave and both end up inside the critical section (a double-acquire);
      `lib/arbiter.sh:192-225` already has the guarded reap — same rule, two places, one
      unsafe.
    - **Fix:** Block when the active ticket has no owns; reuse the arbiter's guarded reap in
      `_lease_lock`.
    - **If we skip it:** The disjoint-ownership guarantee leaks through two independent doors.

16. **`partition_suggest` drops root-level files** (`lib/partition.sh:492-502`)
    - **What this is:** Suggest proposes an `owns:` line from a ticket's diff by mapping files
      to directories (`sed 's|/[^/]*$||'`).
    - **Problem:** A root-level path (`README.md`, `Makefile`) is left unchanged by the sed,
      so it is treated as a directory, `grep -c "^README.md/"` finds nothing, and the file is
      never emitted — probe-verified: a diff touching `README.md`, `Makefile`, `lib/{a,b,c}.c`
      suggests only `owns: lib/`. The later drift check then records the violation the
      suggestion should have prevented.
    - **Fix:** When a `files` line contains no `/`, emit the file itself.
    - **If we skip it:** Every root-file ticket dispatches under-owned.

17. **Teardown on a daemon blip is destructive, and retires live headless batches** (`lib/lifecycle.sh:82`, `:634-641`, `:529-546`)
    - **What this is:** `swarm_down` resolves the workspace via `herdr workspace list … ||
      true` — a daemon error and a clean match are indistinguishable.
    - **Problem:** If the daemon is down or blips mid-teardown, `ws_id` comes back empty and
      the "Already clean" path retires all isolated worktrees (checkpoint+salvage+force
      remove) and deletes the channel dir while panes/agents may still be alive — salvage
      copies race live writers, and a concurrently running headless batch (designed-for per
      HL-LEDGER-1; `_swarm_retire_worktrees` does no liveness check on the holder) loses its
      worktree mid-write. `swarm_status` (`:424-427`) already does the missing check.
    - **Fix:** Fail loudly when `herdr workspace list` itself errors (mirror `swarm_status`);
      in `_swarm_retire_worktrees`, skip+warn while the seat's pidfile holds a live pid.
    - **If we skip it:** `down -y` during a blip or a batch reports success over half-torn
      state.

18. **A pane-read blip resurrects expired quota banners** (`lib/quota.sh:47-48`, `:228-233`, `:255-261`)
    - **What this is:** `quota_probe_kind` returns `unknown` both when the pane read *fails*
      and when it read clean; the gate treats any non-`ok:` result as "wall observably
      lifted" and deletes the banner-seen record.
    - **Problem:** Seat walled at T → daemon blip at T+4m clears the record → a later
      successful probe finds the long-expired banner still in scrollback and, with no record,
      registers it as a *fresh* wall for the full countdown — every dispatch defers on text
      that expired hours ago, the false-block starvation the header says the design refuses.
      During the blip itself the gate also reports the account un-walled.
    - **Fix:** Emit `error:pane-read` when the herdr read itself fails (the contract already
      has `error:<msg>`), and clear the seen record only on a true clean-read `unknown`.
    - **If we skip it:** Every daemon blip on an agy seat manufactures hours of false quota
      deferrals.

19. **Dotted repo names are truncated** (`lib/profile.sh:81`)
    - **What this is:** `detect_repo` parses the GitHub owner/repo out of the remote URL with
      `([^\/]+\/[^\/\.]+)` — the repo segment may not contain a dot.
    - **Problem:** `git@github.com:acme/acme.io.git` yields `acme/acme` (probe-verified),
      which passes the validation regex at `:85`, is cached into `profile.env`, and silently
      poisons every `gh -R` call and rendered brief for that target. No test uses a dotted
      repo name.
    - **Fix:** Allow dots and strip only a trailing `.git`:
      `sed -E 's|.*github.com[:/]([^/]+/[^/]+?)(\.git)?$|\1|'`; add a dotted-name test.
    - **If we skip it:** Every dotted-repo target gets a wrong repo slug in its cached
      profile.

20. **The watchdog block is untested and half-wrong** (`loop-bot-herd.sh:1094-1148`; stubbed out by every suite at `tests/test_manual_arbiter.sh:82-83`, `tests/test_autopilot.sh:123-124`)
    - **What this is:** `unpushed_watch` and `credits_watch` run in every `once` pass
      (`:1439-1440`); no suite exercises their real bodies.
    - **Problem:** `unpushed_watch` hardcodes `origin/main` (`:1097`) while the drain honors
      `BASE_BRANCH` — on any non-main base the watchdog silently never fires.
      `credits_watch` does a live authenticated `curl` to openrouter per pass (`:1128-1136`),
      and a malformed response raises inside the inline Python, killing the whole `once` pass.
      A regression in any of this is invisible to CI.
    - **Fix:** Use the configured base branch in `unpushed_watch`; degrade the credits parse
      to a warn; add direct-call tests in the quota-suite style (stub `curl`/config).
    - **If we skip it:** The watchdogs either never fire or occasionally kill passes, and no
      test can tell.

## Deferred smaller findings

One line each, all receipts verified at HEAD. Carried PR #183 items marked (183).

| Ref | Finding | Receipt | Triage |
|-----|---------|---------|--------|
| D1 | "Jittered backoff" always sleeps 0 — integer division `(RANDOM%3+1)/10`; the fallback is unreachable | `lib/worktree.sh:70` | FIX-NOW |
| D2 | `version-check` is wired into nothing (`check: lint test`); VERSION/CHANGELOG drift passes every gate | `Makefile:57` | FIX-NOW |
| D3 | Dead `_lease_write` — zero callers; name suggests it is the locked write path | `lib/partition.sh:312-314` | FIX-NOW |
| D4 | No-op assertion line (`if var=$(true); then :; fi`) | `tests/test_worktree.sh:220` | FIX-NOW |
| D5 | Dead conditional (both branches identical) + duplicate trailing RESET | `lib/telemetry.py:143-146` | FIX-NOW |
| D6 | Sweep salvage lands under `TARGET` (possibly a seat) not `ROOT_WT`, and duplicates `worktree_prune`'s checkpoint/salvage engine — two copies, diverging safety rules (183) | `scripts/worktree-sweep.sh:307` vs `lib/worktree.sh:203-251` | CHARTER |
| D7 | Sweep `--apply` always exits 0 even when every removal fails (183) | `scripts/worktree-sweep.sh:294-348` | CHARTER |
| D8 | PR #183 has no CHANGELOG entry and the base-RED bullet is stale (124/128+ now attribute nothing) (183) | `CHANGELOG.md` [Unreleased] | FIX-NOW |
| D9 | Dead `worktree unlock` in the force path — locked worktrees `continue` earlier (183) | `scripts/worktree-sweep.sh:343` | FIX-NOW |
| D10 | ARB-DUP-1 cross-ticket holder check reads the queue *outside* the lock; two concurrent enqueues of one sha under different tickets both append | `lib/arbiter.sh:272-284` | CHARTER |
| D11 | `autopilot on` failure leaves a live promote grant for the full TTL, violating its own ordering promise | `lib/cli/stampede-autopilot.sh:93-103` | FIX-NOW |
| D12 | A deleted-but-registered arbiter worktree stalls every drain quietly until an external prune | `lib/arbiter.sh:314-316` | FIX-NOW |
| D13 | `trace_dir` config is silently overridden (`:785`) — one run's events split across two dirs; Ops-pane command built without quoting | `herdr-loop-swarm.sh:712`, `:785` | FIX-NOW |
| D14 | Seat keys with invalid shell charset (`[seats."a b"]`) crash at `eval`/loop-split *after* the workspace and panes exist | `lib/config.sh:226-260` | FIX-NOW |
| D15 | Commented `opencode.jsonc` can never be pinned — strict-JSON gate rejects legal JSONC; fails closed, file intact | `lib/providers.sh:228-231` | ACCEPT |
| D16 | Dead config bindings (`SWARM_WORKSPACE_LABEL`, `SWARM_LOG_PATH`, `SEAT_POS_*`, `SEAT_ROLE_*`); `SWARM_WORKTREE_ROOT` is set-but-ignored — actively misleading | `lib/config.sh:158-161`, `:251-252`; `lib/setup.py:214` | CHARTER |
| D17 | One torn JSONL tail line makes jq fail wholesale → attempt/dead-letter counters read 0 | `lib/headless.sh:246-251`, `:283-284` | CHARTER |
| D18 | Teardown snapshots accumulate forever; nothing prunes them | `lib/lifecycle.sh:566` | CHARTER |
| D19 | `standby_down` drops the lock even when the pane close failed — a live standby can keep dispatching lockless | `lib/standby.sh:239-240` | FIX-NOW |
| D20 | `gh_sync` CREATE assumes repo labels exist; nothing bootstraps them — first `--apply` on a fresh repo fails every create | `lib/gh_sync.sh:589-604` | CHARTER |
| D21 | `--apply --json` prints the plan and exits 0 without applying — an explicit write instruction no-ops | `lib/gh_sync.sh:434-437` | FIX-NOW |
| D22 | `attention next` dumps a raw traceback on a gh failure (non-map path lacks the map path's catch) | `lib/attention.py:397`, `:670-672` | FIX-NOW |
| D23 | `_hl_latest_suite` re-slurps the ever-growing verdict log every 2s poll | `lib/cli/stampede-headless.sh:173-177` | ACCEPT |
| D24 | Empty seat roster crashes the daemon on the bash 3.2 floor (`"${EXPECTED_SEATS[@]}"` unbound) — verified on 3.2.57 | `loop-bot-herd.sh:125-130` | FIX-NOW |
| D25 | `ci-local --gnu-sim` default image (`ubuntu:24.04`) lacks shellcheck/jq — every default run is red by construction, indistinguishable from real divergence | `scripts/ci-local.sh:106-108` | CHARTER |
| D26 | The supervisor's `cmd_watch` loop itself never runs in any suite | `loop-bot-herd.sh:1444` | CHARTER |
| D27 | `stampede version` has no test — a path regression ships silently | `lib/cli/stampede-version.sh` | FIX-NOW |
| D28 | Hard-coded `sleep 3.5`/`sleep 2` in async-gate §2 while the file already owns the `reap_until` poller; the same harvest+sleep incantation repeats 8× | `tests/test_async_gate.sh:199`, `:202` | FIX-NOW |
| D29 | **ARB-TREE-CACHE-1 refile:** skip the integration gate when the candidate tree equals the already-gated integration tip — refile condition ("after the arbiter fixes") is met; `make test` costs 4m21s per gate | `lib/arbiter.sh` drain; postmortem §11.11 | CHARTER |
| D30 | Supervisor usage text omits `drain-queued` | `loop-bot-herd.sh:1477-1488` | FIX-NOW |
| D31 | `DISPATCH_REVIEWER`'s `d1` seat parameter is parsed but never used — dead contract | `loop-bot-herd.sh:649-650` | ACCEPT |
| D32 | `gate_reap`'s RED branch lacks the `_sup_notify` the inline path has | `loop-bot-herd.sh:466-472` | ACCEPT |
| D33 | Concurrent same-seat gate jobs share one `gate-tmp/<seat>` TMPDIR | `loop-bot-herd.sh:307`, `:321` | ACCEPT |

**Dropped candidates:** 53 across the six slices (see Method) — raised, checked, and rejected
at the concrete-case bar; not findings.

---

**Verdict:** fix 1–7 first; 1, 4, 6 and 7 are the wrong-write / data-loss kills.
**Lean:** about −60 lines possible (FIX-NOW deletions D3–D5, D9, D13 ≈ −20; the D6 salvage-engine merge ≈ −40).
**Not checked:** live integrations (herdr daemon, `gh`, network) were never exercised — probes
used scratch repos and stubs; `lib/attention.py` internals rest on the slice audit with the
cited lines spot-verified; `tests/` health was established by the slice audit's full read plus
today's green runs, not a second line-by-line pass; `docs/`, `maps/`, and `briefs/` templates
are out of scope.

## Triage summary

| Class | Count | Items |
|-------|-------|-------|
| FIX-NOW | 11 numbered + 18 deferred | 1–7, 12, 13, 18, 19; D1–D5, D8, D9, D11–D14, D19, D21, D22, D24, D27, D28, D30 |
| CHARTER | 9 numbered + 10 deferred | 8–11, 14–17, 20; D6, D7, D10, D16, D17, D18, D20, D25, D26, D29 |
| ACCEPT | 0 numbered + 5 deferred | D15, D23, D31, D32, D33 |

Numbered findings 12, 13, 18 and 19 are small and mechanical but carry regression-test
obligations, so they ride the FIX-NOW batch after 1–7. Nothing is implemented in this
dispatch; follow-on work is looper's to charter.
