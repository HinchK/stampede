# LOOPER-1 Publish and Hygiene Sprint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the existing LOOPER-1 commits to `origin/main`, then land a four-commit hygiene PR that records the commit-graph repair, aligns docs with bounded-looper seating, resolves two staged tickets, and adds one hermetic happy-path test.

**Architecture:** Two phases with separate merge boundaries. Phase 0 is an as-is push of local `main` at `0028ea9` (three existing commits, no new files). Phase 1 starts only after that push's GitHub `CI` workflow is green: branch `fix/looper-docs-and-hygiene` from `origin/main`, cherry-pick the already-written spec/plan commits, then four conventional commits and one PR. The human merges the PR. Do not push `main` from Phase 1.

**Tech Stack:** Git, GitHub CLI (`gh`), Bash 3.2 test harness (`/bin/bash tests/test_seat_missing.sh`), `make check` / `make version-check`, Markdown docs.

**Spec:** `docs/superpowers/specs/2026-11-05-looper-hygiene-sprint-design.md`

## Global Constraints

- Phase 0 push contains only `6243c6e`, `1df58ac`, and `0028ea9`. Do not amend, squash, or add files to those commits.
- Do not start Phase 1 on a red `origin/main`.
- Do not bump `VERSION` (stays `0.5.0`). `make version-check` must still match the first `## [x.y.z]` changelog heading.
- Docs follow current LOOPER-1 code. Do not rewrite `docs/superpowers/specs/2026-10-13-frontier-swarm-setup-design.md`.
- Tests are hermetic: stub `herdr`, no live panes, no new suite file.
- Ticket work is frontmatter-only on HORIZON-1 and HORIZON-5. Leave P3-4 parked. No GitHub issue edits.
- Commit-graph repair must not `gc --prune`, delete objects, commit `.git/`, or add CI/Makefile/`CONTRIBUTING.md` hooks.
- Base-branch promotion stays human-only. Phase 1 opens a PR; the human merges it.
- Bash 3.2 is the platform floor; add no dependency.

## File structure

| Path | Responsibility |
| --- | --- |
| (no product code in Phase 0) | Existing LOOPER-1 already lives in `herdr-loop-swarm.sh`, `lib/profile.sh`, `lib/briefs.sh`, `lib/lifecycle.sh` |
| `docs/audits/2026-11-05-commit-graph-fsck.md` | Receipt for the local commit-graph rebuild |
| `README.md` | First-run looper wording |
| `docs/user-guide.md` | Launch and restart looper wording |
| `CONTEXT.md` | §9 worktree/looper vocabulary |
| `CHANGELOG.md` | `## [Unreleased]` above `[0.5.0]` |
| `STATE.md` | Prepend 2026-11-05 checkpoint; keep history |
| `maps/tickets-staged/horizon-1-integrate-and-promote.md` | `status: resolved` |
| `maps/tickets-staged/horizon-5-parked-triage.md` | `status: resolved` |
| `tests/test_seat_missing.sh` | Scenario K happy-path `status` + `verify` |
| `docs/superpowers/specs/2026-11-05-looper-hygiene-sprint-design.md` | Already committed on `docs/looper-hygiene-sprint-spec` as `9b322e1`; cherry-pick onto the hygiene branch |
| `docs/superpowers/plans/2026-11-05-looper-hygiene-sprint.md` | This plan; cherry-pick onto the hygiene branch |

Do not create `tests/test_bounded_looper.sh`. Do not modify `lib/profile.sh` unless scenario K proves a real status/verify bug.

---

### Task 1: Phase 0 — push LOOPER-1 and wait for CI

**Files:** none (publish existing commits only)

**Interfaces:**
- Consumes: local `main` at `0028ea98e6fd8c4586f6bdb952f20a3cc26dc9ab`
- Produces: `origin/main` at that same SHA; green GitHub workflow named `CI` on that push

- [ ] **Step 1: Confirm local `main` is exactly the three LOOPER-1 commits**

```bash
git checkout main
git log --oneline origin/main..HEAD
git status --short --branch
```

Expected:

```text
0028ea9 Merge fix/looper-seat-and-none-placeholders (#LOOPER-1)
1df58ac docs: drop the stale suite list from the agent guide
6243c6e fix: seat the looper agent under bounded mode and reject 'none' placeholders (#LOOPER-1)
## main...origin/main [ahead 3]
```

Working tree must be clean. If `HEAD` is not `0028ea9`, or extra files are staged, stop.

- [ ] **Step 2: Push `main` as-is**

```bash
git push origin main
```

Expected: remote accepts three commits. Do not `--force`.

- [ ] **Step 3: Wait for GitHub `CI` on that push**

```bash
git rev-parse origin/main
gh run list --branch main --workflow CI -L 5
```

`origin/main` must print `0028ea98e6fd8c4586f6bdb952f20a3cc26dc9ab`. Identify the `CI` run for that SHA and watch it:

```bash
gh run watch <run-id>
```

Expected: `CI` conclusion `success`. If it is red, stop this plan. Fix on a follow-up branch from `origin/main`; do not start Task 2.

- [ ] **Step 4: Record Phase 0 done**

No commit. Phase 0 is the push itself.

---

### Task 2: Open the hygiene branch

**Files:** none created here; brings already-written spec/plan onto the branch via cherry-pick

**Interfaces:**
- Consumes: green `origin/main` at `0028ea9`; spec commit `9b322e1` on `docs/looper-hygiene-sprint-spec`; this plan's commit on that same branch if present
- Produces: local branch `fix/looper-docs-and-hygiene` from `origin/main` with spec/plan present

- [ ] **Step 1: Create the branch from the published tip**

```bash
git fetch origin
git checkout -b fix/looper-docs-and-hygiene origin/main
git rev-parse HEAD
```

Expected: `HEAD` is `0028ea9…`.

- [ ] **Step 2: Cherry-pick the spec (and this plan if it is a separate commit)**

```bash
git cherry-pick 9b322e1
git log --oneline docs/looper-hygiene-sprint-spec -5
```

If this plan file is not in `9b322e1`, cherry-pick its commit from `docs/looper-hygiene-sprint-spec` as well, or copy the file onto the branch and commit:

```bash
git add docs/superpowers/plans/2026-11-05-looper-hygiene-sprint.md
git commit -m "$(cat <<'EOF'
docs: add LOOPER-1 hygiene sprint plan

EOF
)"
```

Do not cherry-pick anything from `main` that is not already on `origin/main`.

---

### Task 3: Rebuild the commit-graph and write the audit

**Files:**
- Create: `docs/audits/2026-11-05-commit-graph-fsck.md`
- Do not modify: `.git/` (rebuild in place, never stage it)

**Interfaces:**
- Consumes: current local Git object store
- Produces: rebuilt commit-graph; audit Markdown with commands, exit codes, OIDs, and conclusion

- [ ] **Step 1: Capture the failing `fsck`**

```bash
git fsck --full --no-dangling > /tmp/fsck-before.txt 2>&1
echo "exit=$?"
```

Record every `Could not read <oid>` / `failed to parse commit` line. Do not `gc --prune`. Do not `git rm` objects.

- [ ] **Step 2: Rebuild the commit-graph**

```bash
git commit-graph write --reachable --changed-paths
```

If that command errors because a split graph is present, remove only the graph files and rewrite:

```bash
rm -f .git/objects/info/commit-graph
rm -rf .git/objects/info/commit-graphs
git commit-graph write --reachable --changed-paths
```

- [ ] **Step 3: Re-run `fsck`**

```bash
git fsck --full --no-dangling > /tmp/fsck-after.txt 2>&1
echo "exit=$?"
```

If exit is not 0 and missing objects remain, **stop**. Write the audit with conclusion “real object-store loss” and do not claim health. Do not continue to Task 4 until a human unblocks that finding.

- [ ] **Step 4: Write the audit from the captured output**

Create `docs/audits/2026-11-05-commit-graph-fsck.md` using the real OIDs and exit codes from `/tmp/fsck-before.txt` and `/tmp/fsck-after.txt`. Fill every `REPLACE` from those files; do not invent OIDs:

```markdown
# Commit-graph fsck diagnosis — 2026-11-05

**Date:** 2026-11-05 · **Author:** hygiene sprint · **Scope:** local clone of `HinchK/stampede`

## Commands

```bash
git fsck --full --no-dangling
git commit-graph write --reachable --changed-paths
git fsck --full --no-dangling
```

## Before

- Exit code: REPLACE_BEFORE_EXIT
- Unreadable commit-graph OIDs:

```
REPLACE_BEFORE_OID_LINES
```

## After

- Exit code: REPLACE_AFTER_EXIT
- Missing objects remaining: none | list them

## Conclusion

REPLACE_ONE_OF:
- Stale commit-graph: rewrite made `git fsck --full --no-dangling` exit 0. Reachable history was intact; the graph files named deleted commits.
- Real object-store loss: listed OIDs remain unreadable after rewrite. Stopped the hygiene sprint.

No objects were pruned. `.git/` was not committed.
```

- [ ] **Step 5: Commit**

```bash
git add docs/audits/2026-11-05-commit-graph-fsck.md
git commit -m "$(cat <<'EOF'
docs: record commit-graph fsck diagnosis

EOF
)"
```

---

### Task 4: Align looper and profile docs

**Files:**
- Modify: `README.md:34-37`
- Modify: `docs/user-guide.md:47-52` and `docs/user-guide.md:128-132`
- Modify: `CONTEXT.md` §9 (the paragraph starting “The bounded setup gives every standing model seat”)
- Modify: `CHANGELOG.md` (insert above the `[0.5.0]` heading)
- Modify: `STATE.md:1-11` (prepend; do not delete the historical log)
- Do not modify: `VERSION`, `docs/superpowers/specs/2026-10-13-frontier-swarm-setup-design.md`

**Interfaces:**
- Consumes: LOOPER-1 behavior already on `main` (bounded looper is a critical seated AGY agent; Ops panes are agentless; `REPO_LOCAL_ONLY=1`; `TEST_CMD` rejects `none`/`true`)
- Produces: user-facing copy that no longer calls the default looper agentless; `[Unreleased]` changelog; 2026-11-05 `STATE.md` checkpoint

- [ ] **Step 1: Prove the stale wording is still present**

```bash
grep -n 'without persistent model' README.md
grep -n 'agentless worklog pane' CONTEXT.md
grep -n 'transient looper always starts fresh' docs/user-guide.md
grep -n '^## \[Unreleased\]' CHANGELOG.md || true
```

Expected: the three greps match; `[Unreleased]` is absent.

- [ ] **Step 2: Replace the README looper paragraph**

Replace `README.md` lines 34–37:

```markdown
Every standing model seat uses an isolated Git worktree. The bounded looper
is a seated AGY agent (critical: launch it or fail closed). Ops worklog,
troubleshooting, and handoff panes run without model sessions. Each looper
decision is one fresh AGY turn; usage is recorded in
`.herdr-swarm/looper-usage.jsonl`.
```

- [ ] **Step 3: Replace the user-guide launch and restart sentences**

Replace `docs/user-guide.md` lines 47–52:

```markdown
The first launch builds the Herdr layout, seats the chosen model agents
(including the bounded looper), starts the supervisor, and opens model-free
worklog, troubleshooting, and handoff panes in Ops. Each looper decision
uses one fresh, bounded AGY call from durable state; the Herdr agent seat
persists while the swarm is up. Usage is recorded in
`.herdr-swarm/looper-usage.jsonl`. A repeated launch reuses managed panes
and live seats.
```

Replace `docs/user-guide.md` lines 128–132:

```markdown
After a Herdr server restart, eligible native agent conversations resume only
if current Herdr integrations supplied session references. Check them with
`herdr integration status`. Each bounded looper decision starts from durable
state on its next event; the looper agent seat persists while the swarm is
up. A teardown snapshot records evidence; it is not a live conversation
restore.
```

- [ ] **Step 4: Replace CONTEXT.md §9 looper sentence**

In `CONTEXT.md` §9, replace:

```text
The looper is an agentless worklog pane; its bounded AGY decisions run separately.
```

with:

```text
The bounded looper is a non-isolated root agent seat (not an isolated worktree, not an agentless worklog pane); worklog/troubleshooting/handoff panes remain agentless. Bounded AGY decisions run from durable state while that agent seat is up. Legacy unbounded configurations may still use a root coordinator looper — that is not the first-run path.
```

Keep the rest of §9 (isolated worker worktrees, ledger, salvage) unchanged.

- [ ] **Step 5: Insert the Unreleased changelog section**

In `CHANGELOG.md`, insert this block immediately above `## [0.5.0] — 2026-10-05 ...`. Do not change `VERSION`.

```markdown
## [Unreleased]

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

```

- [ ] **Step 6: Prepend the STATE.md checkpoint**

Insert this block after the title line of `STATE.md` and before `**Updated:** 2026-10-08`. Leave everything from the 2026-10-08 header downward intact.

```markdown
**Updated:** 2026-11-05  
**HEAD after Phase 0:** `0028ea9` on `origin/main` (LOOPER-1 published)  
**Suites:** 27, `make check` green locally at report time  
**Now:** hygiene branch `fix/looper-docs-and-hygiene` — commit-graph audit, docs/changelog alignment, HORIZON-1/HORIZON-5 frontmatter, `test_seat_missing.sh` scenario K.  
**Not doing:** version bump, live Herdr, P3-4, 2026-10-13 frontier spec rewrite.

---

```

- [ ] **Step 7: Verify docs and version-check**

```bash
grep -n 'agentless worklog pane' CONTEXT.md && echo 'FAIL: stale CONTEXT' && exit 1 || true
grep -n 'without persistent model' README.md && echo 'FAIL: stale README' && exit 1 || true
grep -n 'transient looper always starts fresh' docs/user-guide.md && echo 'FAIL: stale user-guide' && exit 1 || true
grep -n 'bounded looper' README.md docs/user-guide.md CONTEXT.md
make version-check
```

Expected: stale greps match nothing; `bounded looper` appears in the three docs; `version-check: 0.5.0 == [0.5.0] ✓`.

- [ ] **Step 8: Commit**

```bash
git add README.md docs/user-guide.md CONTEXT.md CHANGELOG.md STATE.md
git commit -m "$(cat <<'EOF'
docs: align looper/profile docs with LOOPER-1

EOF
)"
```

---

### Task 5: Resolve HORIZON-1 and HORIZON-5 frontmatter

**Files:**
- Modify: `maps/tickets-staged/horizon-1-integrate-and-promote.md` line 5 only
- Modify: `maps/tickets-staged/horizon-5-parked-triage.md` line 5 only
- Do not modify: `maps/tickets-parked/arbiter-batch-integration.md`, any other `maps/tickets/**` status, GitHub issues

**Interfaces:**
- Consumes: BRIEF-1 promotion recorded in `STATE.md` (`32dc565` / `755227a`); parked-queue audit `docs/audits/2026-09-30-parked-queue-triage.md`
- Produces: both staged tickets `status: resolved`; files remain in `maps/tickets-staged/`

- [ ] **Step 1: Confirm the current statuses**

```bash
grep -n '^status:' maps/tickets-staged/horizon-1-integrate-and-promote.md maps/tickets-staged/horizon-5-parked-triage.md maps/tickets-parked/arbiter-batch-integration.md
```

Expected: the two staged files say `backlog`; parked P3-4 is still `backlog`.

- [ ] **Step 2: Flip only those two status lines**

In `maps/tickets-staged/horizon-1-integrate-and-promote.md`:

```yaml
status: resolved
```

In `maps/tickets-staged/horizon-5-parked-triage.md`:

```yaml
status: resolved
```

Do not edit ticket bodies. Do not move files.

- [ ] **Step 3: Confirm P3-4 and file locations**

```bash
grep '^status:' maps/tickets-staged/horizon-1-integrate-and-promote.md maps/tickets-staged/horizon-5-parked-triage.md maps/tickets-parked/arbiter-batch-integration.md
ls maps/tickets-staged/horizon-1-integrate-and-promote.md maps/tickets-staged/horizon-5-parked-triage.md maps/tickets-parked/arbiter-batch-integration.md
```

Expected: staged pair `resolved`; parked file `backlog` and still under `maps/tickets-parked/`.

- [ ] **Step 4: Commit**

```bash
git add maps/tickets-staged/horizon-1-integrate-and-promote.md maps/tickets-staged/horizon-5-parked-triage.md
git commit -m "$(cat <<'EOF'
docs: resolve HORIZON-1 and HORIZON-5 frontmatter

BRIEF-1 was promoted (32dc565 / 755227a). Parked-queue triage is in
docs/audits/2026-09-30-parked-queue-triage.md. P3-4 stays parked.

EOF
)"
```

---

### Task 6: Hermetic happy-path status and verify (scenario K)

**Files:**
- Modify: `tests/test_seat_missing.sh` (append scenario K before the final `PASS` line)
- Test: `/bin/bash tests/test_seat_missing.sh`
- Do not create: `tests/test_bounded_looper.sh`
- Do not modify: `tests/test_frontier_launch.sh`, `tests/test_profile.sh`

**Interfaces:**
- Consumes: existing `make_env` and `force_looper_agy` in `tests/test_seat_missing.sh`; `bin/stampede status` → `herdr-loop-swarm.sh status` → `swarm_status`; `bin/stampede verify` → `swarm_verify_seats`
- Produces: scenario K asserting live looper agent on `status` and `verify` exit 0 after a successful bounded `yeehaw.sh start`

LOOPER-1 launch behavior already exists (scenarios G/H/I/J). This task adds coverage, not a new launcher. If K fails, fix the **test fixture** (fake `herdr` handlers) first. Change production code only if `status`/`verify` really omit the looper after a healthy G-style launch.

- [ ] **Step 1: Write scenario K before the suite's PASS line**

In `tests/test_seat_missing.sh`, insert this block immediately above `printf 'test_seat_missing: PASS\n'`:

```bash
echo "==> K: after a healthy bounded launch, status names the looper agent and verify exits 0"
make_env
force_looper_agy "$ENV_DIR/fresh project"
"$ENV_DIR/yeehaw.sh" start --brainstorm --topic "looper happy path" > "$ENV_DIR/up.log" 2>&1 \
  || { echo "K: up failed with a healthy looper chain" >&2; tail -30 "$ENV_DIR/up.log" >&2; exit 1; }
"$ROOT/bin/stampede" status "$ENV_DIR/fresh project" > "$ENV_DIR/status.log" 2>&1 \
  || { echo "K: status failed after healthy launch" >&2; cat "$ENV_DIR/status.log" >&2; exit 1; }
grep -E 'looper-.*agy' "$ENV_DIR/status.log" \
  || { echo "K: status does not name the looper as an agy agent" >&2; cat "$ENV_DIR/status.log" >&2; exit 1; }
if grep -E 'looper-' "$ENV_DIR/status.log" | grep -Eqi 'agentless|[[:space:]]shell[[:space:]]'; then
  echo "K: status describes the looper as agentless/shell" >&2
  grep -E 'looper-' "$ENV_DIR/status.log" >&2
  exit 1
fi
if grep -qi 'suite gate' "$ENV_DIR/status.log"; then
  echo "K: status printed a suite-gate warning with a runnable TEST_CMD" >&2
  cat "$ENV_DIR/status.log" >&2
  exit 1
fi
set +e
"$ROOT/bin/stampede" verify "$ENV_DIR/fresh project" > "$ENV_DIR/verify.log" 2>&1
k_rc=$?
set -e
[[ "$k_rc" -eq 0 ]] || { echo "K: verify exited $k_rc after healthy launch" >&2; cat "$ENV_DIR/verify.log" >&2; exit 1; }
```

- [ ] **Step 2: Run the focused suite**

```bash
/bin/bash tests/test_seat_missing.sh
```

Expected: `test_seat_missing: PASS`.

If K hangs on `verify`, the fake `herdr` in this file is treating `pane wait-output` as a 30s no-op instead of success. Add these branches to the stub **before** the final `else:` in `make_env`'s `herdr` script (do not change production `seat_wait_ready`):

```python
elif a[:2] == ['pane', 'wait-output']:
    emit({})
elif a[:2] == ['agent', 'wait']:
    emit({})
```

Re-run `/bin/bash tests/test_seat_missing.sh`.

If K fails because `status` has no `looper-`/`agy` line after a successful G-style launch, that is a production bug: inspect `swarm_status` in `lib/lifecycle.sh` (Seated Agents uses `herdr agent list` filtered by workspace). Fix the smallest status formatting/filter bug; do not change launch seating.

- [ ] **Step 3: Commit**

```bash
git add tests/test_seat_missing.sh
git commit -m "$(cat <<'EOF'
test: assert bounded looper status and verify happy path

EOF
)"
```

---

### Task 7: Full gate and pull request

**Files:** none new; reviews the branch diff

**Interfaces:**
- Consumes: four hygiene commits plus cherry-picked spec/plan
- Produces: green `make check`; PR into `origin/main`; human merge (do not `git push origin main`)

- [ ] **Step 1: Run the suite gate**

```bash
make check
```

Expected: lint clean; `All suites green (27)`; `version-check` still `0.5.0`.

- [ ] **Step 2: Inspect the branch**

```bash
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
```

Expected commits (spec/plan cherry-picks may appear first):

```text
test: assert bounded looper status and verify happy path
docs: resolve HORIZON-1 and HORIZON-5 frontmatter
docs: align looper/profile docs with LOOPER-1
docs: record commit-graph fsck diagnosis
```

Diff must not include `VERSION` or `docs/superpowers/specs/2026-10-13-frontier-swarm-setup-design.md`.

- [ ] **Step 3: Push the branch and open a PR**

```bash
git push -u origin HEAD
gh pr create --title "docs+test: LOOPER-1 hygiene (docs, tickets, commit-graph, scenario K)" --body "$(cat <<'EOF'
## Summary
- Record the local commit-graph fsck repair in `docs/audits/2026-11-05-commit-graph-fsck.md`.
- Align README, user guide, CONTEXT, CHANGELOG `[Unreleased]`, and STATE checkpoint with LOOPER-1 (bounded looper is a seated agent).
- Mark HORIZON-1 and HORIZON-5 resolved; P3-4 stays parked.
- Add `tests/test_seat_missing.sh` scenario K: healthy bounded launch → `stampede status` names the looper → `stampede verify` exits 0.

## Test plan
- [x] `make check`
- [ ] GitHub `CI` on this PR
- [ ] Confirm `VERSION` is still 0.5.0

EOF
)"
```

- [ ] **Step 4: Wait for PR CI; do not merge**

```bash
gh pr checks
```

If red, fix on this branch and push. Do not merge. Do not push `main`. Tell the human the PR URL.

---

## Spec coverage (self-review)

| Spec requirement | Task |
| --- | --- |
| Direct-push `0028ea9`; no extra files on those commits | Task 1 |
| Wait for `CI`; stop if red | Task 1 |
| Branch `fix/looper-docs-and-hygiene` from `origin/main` | Task 2 |
| Four conventional commits + one PR; human merges | Tasks 3–7 |
| Commit-graph rebuild + audit; no prune/CI hook | Task 3 |
| README / user-guide / CONTEXT / CHANGELOG Unreleased / STATE prepend | Task 4 |
| No VERSION bump; no 2026-10-13 spec rewrite | Task 4 constraints |
| HORIZON-1 / HORIZON-5 `resolved`; stay in `tickets-staged/`; P3-4 parked | Task 5 |
| Scenario K in `test_seat_missing.sh`; no new suite | Task 6 |
| `make check` before PR | Task 7 |
