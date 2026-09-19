---
id: T-009
title: "Telemetry Event Schema and Live Ops Streaming"
type: wayfinder:research
status: open
assignee: unassigned
blocked_by: []
parent: maps/universal-herdr-swarm.md
---

# Telemetry Event Schema and Live Ops Streaming

## Question

What standard JSONL event contract should `telemetry.py` and `agent_guard.sh` enforce to record session dispatches, worker transitions, suite gate verdicts, and circuit breaker events, and how should the Ops log pane stream and format these events in real time without unbounded terminal noise?
