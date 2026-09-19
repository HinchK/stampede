---
id: T-015a
title: "README Truth: Align Documentation with Shipped Architecture"
type: wayfinder:prototype
status: resolved
assignee: looper
prototype_asset: README.md
parent: maps/universal-herdr-swarm.md
resolution:
  verified_by: looper
  date: "2026-09-19"
---

# README Truth: Align Documentation with Shipped Architecture (T-015a)

## Question

How should `README.md` be updated to accurately reflect the real, shipped capabilities of `loop-bot-herd-agy` (modular libraries in `lib/`, fail-closed profiling, physical CWD workspace lookup, (ticket, sha) verdict deduplication), striking unintegrated or nonexistent claims (telemetry stream, circuit breakers)?

## Preamble

1. **Intended Outcome**: Update `README.md` to accurately document the current operational architecture, removing fictional components (`lib/agent_guard.sh`, active `telemetry.py` streaming) and documenting the real modular foundation (`lib/profile.sh`, `lib/lifecycle.sh`, `lib/preflight.sh`, `lib/config.sh`, `lib/briefs.sh`, `lib/common.sh`).
2. **Explicit Done-Criteria**:
   - Strike mentions of `lib/agent_guard.sh` and claims of active circuit-breaker daemon.
   - Clarify `telemetry.py` as an upcoming telemetry event schema rather than live stream.
   - Document the real modular libraries in `lib/`: `common.sh`, `profile.sh`, `lifecycle.sh`, `preflight.sh`, `config.sh`, `briefs.sh`, `layout_engine.sh`.
   - Document the fail-closed profile policy (no kultivait default, no fake-green `true` test fallback).
   - Document the `(ticket, sha)` verdict deduplication protocol.
   - Update file tree to reflect the actual repository files.
3. **Verification Step**: Run:
   `grep -E 'agent_guard\.sh' README.md && exit 1 || grep -q 'profile\.sh' README.md && echo "PASS: README truthful"`

## Verification Log

- Cleaned `README.md` of fictitious claims (`lib/agent_guard.sh`, unintegrated telemetry streams).
- Documented all 7 active modular libraries in `lib/` and their respective roles.
- Documented fail-closed profile policy, safe physical CWD lifecycle, and `(ticket, sha)` supervisor protocol.
- Verified `grep -E 'agent_guard\.sh' README.md && exit 1 || grep -q 'profile\.sh' README.md && echo "PASS: README truthful"` passed cleanly.
