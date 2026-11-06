# Stampede: LOOPER-1 publish and hygiene sprint

**Status:** Design approved in conversation, 2026-11-05. Spec written for review before the implementation plan.

**Source:** `stampede-repo-report-2026-11-05.md` (parent of this repository) sprint suggestions 1–5, refined through brainstorming. The report is not in this tree.

## Intent

Close the operational and documentation gap left by LOOPER-1. The behavior change already exists on local `main` at `0028ea9`. This sprint publishes that work, then aligns docs, Git metadata receipts, two stale staged tickets, and one hermetic happy-path test with what the code actually does.

This is not a new feature. Bounded looper seating, `REPO_LOCAL_ONLY`, and `TEST_CMD` placeholder rejection are already implemented and covered by fail-closed tests. The sprint makes that work remotely verified and operator-visible.

## Locked decisions

- Sequence: publish the existing three commits first; start hygiene only after that push's GitHub `CI` workflow is green.
- Publish method: direct push of local `main` (`0028ea9`) to `origin/main`. No extra files on those commits.
- Hygiene shape: one branch, four conventional commits, one PR. Do not push `main` from Phase 1.
- Tests: hermetic contract gap-fill in `tests/test_seat_missing.sh`. Stub `herdr`. No live panes. No new suite file.
- `STATE.md`: prepend a short 2026-11-05 checkpoint; keep the historical log.
- Commit-graph: local rebuild plus `docs/audits/2026-11-05-commit-graph-fsck.md`. No CI hook, no `CONTRIBUTING.md` recipe.
- Tickets: set HORIZON-1 and HORIZON-5 to `resolved`, cite existing promote/audit commits, leave both in `maps/tickets-staged/`, leave P3-4 parked. No other frontmatter sweep.
- Changelog: add `## [Unreleased]` above `[0.5.0]`. Do not bump `VERSION` (`0.5.0`).
- Docs follow current LOOPER-1 code. Do not rewrite `docs/superpowers/specs/2026-10-13-frontier-swarm-setup-design.md`.

## Phase 0 — publish LOOPER-1

Local `main` is three commits ahead of `origin/main`:

| Commit | Role |
| --- | --- |
| `6243c6e` | LOOPER-1: bounded looper is a real agent seat; reject `none` placeholders; surface suite-gate warnings |
| `1df58ac` | Drop the stale suite list from `CLAUDE.md` |
| `0028ea9` | Merge of that branch onto `main` |

Push `main` to `origin/main` as-is. Do not amend, squash, or add hygiene files to this push.

Wait for GitHub workflow `CI` on that push. If it is red, stop. Fix on a follow-up branch from `origin/main`; do not start Phase 1 on a red default branch.

Phase 0 is done when `origin/main` contains `0028ea9` and that push's `CI` run is green.

## Phase 1 — hygiene PR

After Phase 0 CI is green, create `fix/looper-docs-and-hygiene` from `origin/main`. Land four commits, then open a PR into `origin/main`. The human merges after the PR's CI is green.

### Commit 1 — commit-graph receipt

The current `git fsck --full --no-dangling` exits 16 because the local commit-graph names twelve unreadable commit OIDs. That is Git metadata, not product code.

1. Rebuild with `git commit-graph write --reachable` (or delete the stale `commit-graph` / `commit-graphs` under `.git/objects/info/` and rewrite). Do not `gc --prune`. Do not delete objects.
2. Re-run `git fsck --full --no-dangling`.
3. Write `docs/audits/2026-11-05-commit-graph-fsck.md` with: commands, before/after exit codes, the twelve OIDs, whether any missing object remained, and the conclusion (stale graph vs real object-store loss).
4. If objects are still missing after rewrite, stop and report. Do not ship an audit that claims the store is healthy.

Do not commit anything under `.git/`. Do not add a Makefile or CI check for this.

### Commit 2 — docs and changelog

Docs describe **current default behavior**: setup writes `bounded_looper = true`, and that looper is a critical seated agent of its configured kind (AGY this release).

Three surfaces, stated the same way in each user-facing file:

1. **Bounded looper (default):** critical seated agent. Launch it like other seats, or fail closed. `status` / `verify` treat an agentless or shell looper as unhealthy.
2. **Worklog, troubleshooting, handoff:** agentless panes. They stay model-free.
3. **Legacy unbounded configs:** may still use a root coordinator looper. That is not the first-run path.

File edits:

- `README.md` (currently ~34–37): remove “looper pane runs without a persistent model session.” The bounded looper is a seated AGY agent; Ops panes are model-free; usage still lands in `.herdr-swarm/looper-usage.jsonl`.
- `docs/user-guide.md` (currently ~49–51 and ~130): same split. Replace “transient looper always starts fresh” with: each bounded decision is one AGY turn from durable state; the Herdr agent seat persists while the swarm is up.
- `CONTEXT.md` §9: the looper is not “an agentless worklog pane.” Standing worker seats stay isolated; the looper remains a non-isolated root seat (already asserted in `tests/test_frontier_launch.sh`).
- `CHANGELOG.md`: insert `## [Unreleased]` above `## [0.5.0]`. Record LOOPER-1: `REPO="none"` rejected; local-only uses `REPO_LOCAL_ONLY=1`; `TEST_CMD` refuses `""` / `none` / `true`; bounded looper is a critical agent; suite-gate warnings on `up` and `status`. `make version-check` still matches `VERSION` to the first `## [x.y.z]` line (`0.5.0`).
- `STATE.md`: prepend a short 2026-11-05 checkpoint (Phase 0 HEAD, 27 suites, LOOPER-1 shipped, Phase 1 branch). Leave the historical log.

Do not bump `VERSION`. Do not rewrite the 2026-10-13 frontier spec.

### Commit 3 — two staged tickets

Frontmatter only. No ticket-body rewrites. No GitHub issue edits.

- `maps/tickets-staged/horizon-1-integrate-and-promote.md`: `status: resolved`. Cite BRIEF-1 promotion (`32dc565` / `755227a` as recorded in `STATE.md`).
- `maps/tickets-staged/horizon-5-parked-triage.md`: `status: resolved`. Cite `docs/audits/2026-09-30-parked-queue-triage.md`.
- Leave both files in `maps/tickets-staged/`.
- Leave `maps/tickets-parked/arbiter-batch-integration.md` parked/backlog. Do not implement P3-4.
- Do not normalize other `done` / `closed` / `resolved` tickets.

### Commit 4 — hermetic happy path

`tests/test_seat_missing.sh` already covers:

- G: bounded launch records looper as `agy`, `agentless == false`
- H: refused looper launch fails closed
- I: stale agentless ledger fails `verify`
- J: suite-gate warning on `status` / `up`

Add scenario **K** in that file, using the same stub-`herdr` fixture as G. After a successful bounded `yeehaw.sh start`:

1. `stampede status <target>` names the looper as a live agent seat (not agentless/shell) and does not print the suite-gate warning when `TEST_CMD` is runnable.
2. `stampede verify <target>` exits 0.

Do not add `tests/test_bounded_looper.sh`. Do not restub launch in `tests/test_frontier_launch.sh`. Profile placeholder cases stay in `tests/test_profile.sh`.

## Error handling and gates

- Phase 0 CI red → stop; no hygiene branch from a red `main`.
- Commit-graph rewrite still missing objects → stop; do not claim health in the audit.
- Phase 1 `make check` must be green before opening the PR, including the extended `test_seat_missing.sh` and `make version-check`.
- Phase 1 PR CI red → fix on the same branch; do not merge.

## Out of scope

- Version bump or `v0.5.1` tag
- Live Herdr smoke
- Rewriting `STATE.md` history
- Rewriting the 2026-10-13 frontier spec
- Ticket body edits, file moves, or a full `maps/tickets/**` status sweep
- Commit-graph CI / Makefile / `CONTRIBUTING.md` recipe
- Implementing parked P3-4
- Amending or squashing the three Phase 0 commits

## Acceptance

- `origin/main` contains `0028ea9` and Phase 0 `CI` is green
- `fix/looper-docs-and-hygiene` PR is green and merged by the human
- `make check` green locally on that branch
- `README.md`, `docs/user-guide.md`, and `CONTEXT.md` no longer describe the default bounded looper as agentless
- `CHANGELOG.md` has `[Unreleased]`; `VERSION` remains `0.5.0`
- `STATE.md` starts with a 2026-11-05 checkpoint
- HORIZON-1 and HORIZON-5 are `resolved` in `maps/tickets-staged/`
- P3-4 remains parked
- `docs/audits/2026-11-05-commit-graph-fsck.md` exists and matches the post-repair `git fsck` result
- `tests/test_seat_missing.sh` scenario K covers healthy `status` and `verify` after bounded looper seating
