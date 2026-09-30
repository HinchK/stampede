---
id: HEADLESS-1
title: "Dispatch calls don't pass --no-focus, stealing the human's pane focus on every herd prompt"
type: wayfinder:defect
status: resolved
commit: c8fbad2980971cc6b331f5cb1e7ae8f3275dd326
assignee: arch
owns: loop-bot-herd.sh,herdr-loop-swarm.sh,briefs/looper.in.md
parent: maps/universal-herdr-swarm.md
resolution:
  commit: c8fbad2980971cc6b331f5cb1e7ae8f3275dd326
  outcome: premise-disproven
  integrated_at: c8fbad2
  integration_ref: swarm/stampede/integration
  reviewer_verdict: PASS
  review_file: .herdr-swarm/reviews/HEADLESS-1-c8fbad2980971cc6b331f5cb1e7ae8f3275dd326.md
  findings_file: docs/findings/herdr-semantics.md#f-agent-prompt-focus-semantics-headless-1
github_issue: 74
github_url: "https://github.com/HinchK/stampede/issues/74"
synced_at: "2026-09-30T17:16:14Z"
---

# HEADLESS-1 — stop stealing focus on dispatch

## Intended Outcome

Every place this repo's own code (or its briefs, which instruct `looper`) calls `herdr agent prompt` for
background dispatch passes `--no-focus`, so routine ticket dispatch stops switching the human's visible pane away
from whatever they're actually looking at. The `herdr` CLI already supports this — nothing to build, just an audit
and a flag.

## Background

Confirmed this session: `pm`'s own `herdr agent prompt looper-hinchk-stampede "..." --wait --timeout 120000` calls
(used repeatedly to dispatch the `Prove and Reconcile` and `TRUST-1` epics) never passed `--no-focus`, meaning
every single dispatch likely switched the human's visible tab to `looper`'s pane. The herdr skill's own guidance is
explicit: "Use `--no-focus` for background work unless the user asked to switch context." This is the cheap half of
"headless mode" — no architecture change, just an audit.

## Done-Criteria

1. `grep -rn "herdr agent prompt" .` across `loop-bot-herd.sh`, `herdr-loop-swarm.sh`, and any brief that
   instructs an agent to prompt another agent (`briefs/looper.in.md` etc.) — every call for *routine* background
   dispatch gets `--no-focus`.
2. Calls that legitimately want to switch the human's attention (e.g. a blocked/approval-needed state) are left
   alone and the ticket says which ones and why.
3. `make test` green.

## Verification Step

```bash
grep -rn "herdr agent prompt" . --include="*.sh" --include="*.md" | grep -v "no-focus\|test"
# should only list calls with a documented reason to keep focus
```

## Notes

This ticket is scoped narrowly on purpose — it's the well-understood, low-risk half of "headless mode." The bigger
question (a true unattended `--headless` run mode with no panes at all) is HEADLESS-2, a research ticket, because
the destination for that isn't settled yet.

## Resolution

Resolved as **premise-disproven** on `herdr 0.9.1` by `arch-1` in commit `c8fbad2980971cc6b331f5cb1e7ae8f3275dd326`, with autonomous review `PASS` verdict in `.herdr-swarm/reviews/HEADLESS-1-c8fbad2980971cc6b331f5cb1e7ae8f3275dd326.md` and integrated into `swarm/stampede/integration`:

1. **Option Non-existence**: `herdr agent prompt --help` accepts only `--wait`, `--until`, and `--timeout`. Passing `--no-focus` fails with `unknown option: --no-focus`.
2. **Silent Failure Hazard**: Because supervisor prompt dispatches in `loop-bot-herd.sh` and `herdr-loop-swarm.sh` are guarded with `>/dev/null 2>&1 || true`, adding `--no-focus` would have caused every background prompt and dispatch to fail silently.
3. **No Focus Theft**: Live empirical probe confirmed that prompting an idle agent in another tab leaves active pane focus untouched (`focused: true` flag unchanged).
4. **Existing Focus Governance**: The repo's one focus-taking call, `herdr pane split`, already centrally passes `--no-focus` in `lib/layout_engine.sh:16` (`split_pane()`).
5. **Receipts Recorded**: Full empirical findings documented in `docs/findings/herdr-semantics.md` §F and §G.
