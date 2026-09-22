---
id: T-011
title: "Workspace Lifecycle and Clean Teardown Protocol"
type: wayfinder:prototype
status: closed
assignee: looper
prototype_asset: lib/lifecycle.sh
owns: lib/lifecycle.sh
parent: maps/universal-herdr-swarm.md
github_issue: 54
github_url: "https://github.com/HinchK/stampede/issues/54"
synced_at: "2026-09-22T03:50:13Z"
---

# Workspace Lifecycle and Clean Teardown Protocol

## Question

What exact sequence of pane closures, workspace disposal, and process signals constitutes a safe, idempotent `down` and `status` command, and what state artifacts in `.herdr-swarm/` (e.g. `profile.env`, `traces/`, `verdicts.jsonl`) should be preserved across swarm invocations vs cleaned up?

## Resolution

Implemented and validated the lifecycle management protocol in [`lib/lifecycle.sh`](../../lib/lifecycle.sh):
1. **Directory-Aware Resolution:** Resolves target workspace ID from `$HERDR_WORKSPACE_ID`, workspace label matching repository basename, or agent working directory without hardcoded assumptions.
2. **Safe Agent Teardown Sequence:** `swarm_down` queries active agents via `herdr agent list`, identifies panes matching the target workspace ID, and closes agent panes individually before calling `herdr workspace close <ID>` (or optionally retaining the workspace via `--keep-workspace`).
3. **Artifact Retention Policy:** Transient response nonces and IPC pipes in `.herdr-swarm/channel` are cleaned up on teardown, while audit artifacts (`.herdr-swarm/profile.env`, `.herdr-swarm/traces/*.jsonl`, and `verdicts.jsonl`) are strictly preserved.
4. **Rich Status Introspection:** `swarm_status` reports workspace state, detected profile settings (`REPO`, `TEST_CMD`, `ECOSYSTEM`), a formatted table of all seated agents with colorized status (`working`, `idle`, `blocked`), and the latest telemetry events.

