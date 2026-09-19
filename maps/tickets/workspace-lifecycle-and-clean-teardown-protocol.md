---
id: T-011
title: "Workspace Lifecycle and Clean Teardown Protocol"
type: wayfinder:grilling
status: open
assignee: unassigned
blocked_by: []
parent: maps/universal-herdr-swarm.md
---

# Workspace Lifecycle and Clean Teardown Protocol

## Question

What exact sequence of pane closures, workspace disposal, and process signals constitutes a safe, idempotent `down` and `status` command, and what state artifacts in `.herdr-swarm/` (e.g. `profile.env`, `traces/`, `verdicts.jsonl`) should be preserved across swarm invocations vs cleaned up?
