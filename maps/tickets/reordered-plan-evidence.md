---
id: PM-PLAN-EVIDENCE
title: "Reordered execution plan: mark probe-backed vs inspection evidence for D1–D4"
type: wayfinder:doc
status: resolved
commit: babd619
assignee: pm
owns: docs/reordered-plan.md
parent: maps/universal-herdr-swarm.md
github_issue: 43
github_url: "https://github.com/HinchK/stampede/issues/43"
synced_at: "2026-09-22T03:50:13Z"
---

# PM-PLAN-EVIDENCE

`pm` reordered `docs/reordered-plan.md`, marking each D1–D4 decision as
probe-backed (command output quoted) vs inspection-only. STATE.md's header
references this file as the Execution Roadmap; it was previously reachable
only from the `pm-reordered-plan` side branch — integrated to `main` via the
arbiter (see `PM-BRANCH-RECON`).

## Verification Step

    git cat-file -e babd619^{commit} && grep -q "probe" docs/reordered-plan.md
