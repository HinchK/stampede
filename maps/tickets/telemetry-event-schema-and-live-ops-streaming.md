---
id: T-009
title: "Telemetry Event Schema and Live Ops Streaming"
type: wayfinder:research
status: closed
assignee: research
resolution_doc: docs/findings/telemetry-schema.md
parent: maps/universal-herdr-swarm.md
---

# Telemetry Event Schema and Live Ops Streaming

## Question

What standard JSONL event contract should `telemetry.py` and `agent_guard.sh` enforce to record session dispatches, worker transitions, suite gate verdicts, and circuit breaker events, and how should the Ops log pane stream and format these events in real time without unbounded terminal noise?

## Resolution

Investigated codebase and authored specification in `docs/findings/telemetry-schema.md`:
1. **Contract:** Standardized single-envelope JSONL format with hierarchical `domain.action` naming (`agent.dispatch`, `suite.verdict`, `guard.circuit_breaker`, `swarm.lifecycle`) and project-scoped trace directory (`.herdr-swarm/traces/`).
2. **Disconnections Identified:** Corrected 5 root causes of unused telemetry: uncalled `telemetry.py` in launcher, supervisor maintaining competing `session-verdicts.jsonl`, guard printing ANSI instead of logging events, Ops pane tailing empty `/tmp/herdr-process.log`, and missing session-ID inside payload objects.
3. **Live Streaming Engine:** Specified dual-purpose `lib/telemetry.py` featuring a `stream` CLI mode that parses JSONL into 1-line ANSI badge lines strictly clamped to terminal column width, eliminating raw JSON wrapping in 80-column split panes.
