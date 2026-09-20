---
id: P3-3
title: "Asynchronous Supervisor Harvesting and Durable Gate Jobs"
type: wayfinder:prototype
status: backlog
assignee: arch
prototype_asset: loop-bot-herd.sh,tests/test_async_gate.sh
owns: loop-bot-herd.sh,tests/test_async_gate.sh
parent: maps/universal-herdr-swarm.md
---

# Asynchronous Supervisor Harvesting and Durable Gate Jobs (P3-3)

## Context & Problem Statement

In single-worker swarms, the supervisor (`loop-bot-herd.sh`) executes the test suite synchronously during its poll loop. In Phase 3 with $N$ concurrent workers, a long-running test gate (e.g. 60–300s) on one worker completely stalls verdict harvesting for all other workers.

Per [Phase 3 Roadmap](file:///Users/hinchk/Fun/loop-bot-herd-agy/docs/audits/2026-09-19-phase3-concurrent-fanout-roadmap.md) §1.3:
- The suite gate becomes an asynchronous background job with durable state files in `.herdr-swarm/gates/<seat>-<sha7>.job`.
- The supervisor poll loop never blocks. It checks for finished jobs (`rc` file present), re-verifies post-run tree drift, writes verdicts to session logs, and calls `arbiter_enqueue`.
- A concurrency cap (`gate_concurrency`, default 2) bounds CPU and test runner contention.
- Crash safety: On supervisor restart, missing or dead jobs are safely re-queued and never assumed green.

## Preamble

1. **Intended Outcome**: `arch` refactors `loop-bot-herd.sh` harvest loop to execute test suite gates as background jobs with durable tracking and concurrency limits.
2. **Explicit Done-Criteria**:
   - `loop-bot-herd.sh`:
     - Spawns background gate job when worker emits valid verdict and running jobs < `gate_concurrency`.
     - Writes job metadata to `.herdr-swarm/gates/<seat>-<sha7>.job` containing PID, started timestamp, `GATE_DIR`, `sha`, `ticket`.
     - Reaps completed background jobs, validates post-condition drift, logs verdict, and enqueues to arbiter.
     - Never blocks the supervisor poll loop.
   - Quality checks:
     - `shellcheck loop-bot-herd.sh` passes cleanly with 0 warnings.
3. **Verification Step**:
   - Simulate concurrent long-running suite gates and verify non-blocking supervisor polling.
