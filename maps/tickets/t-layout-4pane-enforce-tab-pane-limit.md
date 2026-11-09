---
id: T-LAYOUT-4PANE
title: "Cap tab panes at 4 and isolate logging panels into dedicated logs tab"
type: wayfinder:task
status: resolved
assignee: arch-1-stampede
commit: 7764331
review: .herdr-swarm/reviews/T-LAYOUT-4PANE-7764331.md
owns: herdr-loop-swarm.sh,lib/layout_engine.sh,tests/test_layout_engine.sh
---

# T-LAYOUT-4PANE -- Cap tab panes at 4 and isolate logging panels into dedicated logs tab

## 1. Intended Outcome
Enforce the architectural invariant that no Herdr tab contains more than 4 windows. Move all bounded-looper logging and monitoring panels (telemetry-stream, supervisor, worklog, handoff) from the `ops` tab into a dedicated `logs` tab arranged in a balanced 2×2 grid.

## 2. Explicit Done-Criteria
1. `herdr-loop-swarm.sh` provisions a dedicated `logs` tab for model-free views (`telemetry-stream`, `supervisor`, `worklog`, `handoff`).
2. The `ops` tab contains only interactive agent seats (`docs`, `gh`, `reviewer`, `helper`), capped at <= 4 panes.
3. Every tab in the workspace (`herd`, `ops`, `logs`) has <= 4 panes in a 2×2 grid.
4. Unit/integration tests in `tests/test_layout_engine.sh` assert that no tab ever exceeds 4 panes.
5. `make check` passes with 0 warnings/errors.

## 3. Verification Step
Run:
`make check && bash tests/test_layout_engine.sh`
and verify live tab counts via `herdr tab list --workspace <WS_ID>` show <= 4 panes for every tab.

## Resolution
Resolved in commit `77643314f1f88c590274c4f3f1138929bee53bee` by `arch-1-stampede`.
Review PASS verified in `.herdr-swarm/reviews/T-LAYOUT-4PANE-7764331.md`.
