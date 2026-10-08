---
id: INTEG-REC-1
title: "Manual / fast-forward integration path emits durable session verdict record"
type: wayfinder:task
status: resolved
assignee: arch
owns: lib/arbiter.sh
parent: maps/dispatch-safety-and-review-policy.md
---

# INTEG-REC-1 -- arbiter integration emits durable session verdict record

## Intended Outcome

Whenever a ticket is integrated by `lib/arbiter.sh` (via fast-forward or `--no-ff` merge during `arbiter drain` or manual promotion), arbiter emits a corresponding green verdict record into `.herdr-swarm/session-verdicts.jsonl`, ensuring downstream post-integration documentation sweeps have unbroken verification preconditions.

## Background (citing REVIEW-SHA-1 and CI-FIX-2 integration gaps)

During post-integration sweeps for `REVIEW-SHA-1` and `CI-FIX-2` (2026-10-08), docs sweeps (`agy-docs`) stalled because `.herdr-swarm/session-verdicts.jsonl` lacked a green verdict entry matching the promoted ticket and full SHA.

The root cause is an architectural split between supervisor harvesting and arbiter integration:
1. `loop-bot-herd.sh` writes `.herdr-swarm/session-verdicts.jsonl` when harvesting `ARCH DONE` anchors from agent scrollback.
2. `lib/arbiter.sh` executes the test suite pre-gate on the integrated candidate (`_arb_cmd_runnable`), but records results only in `${ARB_STATE}/gate-logs/arbiter-${ticket}-${sha:0:7}.log` and `${ARB_STATE}/integration.jsonl`. It does not append a corresponding entry to `${STATE_DIR}/session-verdicts.jsonl`.
3. When tickets are fast-forwarded or integrated via arbiter drain or manual operator promotion without looper harvest scrollback, `session-verdicts.jsonl` has a gap.
4. The post-integration sweep mandate (ROUTE-5) strictly requires: "Precondition confirmed: green verdict in .herdr-swarm/session-verdicts.jsonl." A missing record forces manual operator intervention or synthetic harvest re-runs before docs sweeps can proceed.

## Done-Criteria

1. In `lib/arbiter.sh` (`_arb_integrate`): upon successful integration (after the test gate passes and the integration ref updates), append a durable record to `${STATE_DIR}/session-verdicts.jsonl` recording the passing gate.
2. Structure the verdict record consistently with the supervisor schema:
   `{"ts": <unix_ts>, "ticket": "$ticket", "sha": "$sha", "seat": "$seat", "suite": "green", "exit_code": 0, "verdict": "INTEGRATED #$ticket $sha"}`
3. Handle both fast-forward merges and off-branch merge candidates, ensuring canonical full 40-character SHAs are recorded.
4. Add unit test assertions in `tests/test_arbiter.sh` confirming that `arbiter drain` appends the verdict record to `session-verdicts.jsonl` on successful integration.
5. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_arbiter.sh && make check
```

## Resolution (2026-10-08)

Resolved in commit `eb805dd10bf658bca72875e2c54269a06ec2105b` (`eb805dd`).

Delivered across all criteria:
1. **Verdict record on integration**: `lib/arbiter.sh` gained `_arb_verdict_record` (lib/arbiter.sh:86), called from `_arb_integrate` step 4 (lib/arbiter.sh:314) — after the test gate passes AND the CAS ref update succeeds — appending `{"ts": <unix_ts>, "ticket": ..., "sha": ..., "seat": ..., "suite": "green", "exit_code": 0, "verdict": "INTEGRATED #<ticket> <sha>"}` to `${STATE_DIR}/session-verdicts.jsonl`, matching the supervisor's schema (loop-bot-herd.sh:390).
2. **Both merge paths**: the append lives at the single success convergence point, so the fast-forward path and the off-branch `--no-ff` merge path both file the record; conflicts (`conflict`), RED gates (`integration_red`), ungateable gates, and CAS retries file nothing.
3. **Canonical SHAs**: `_arb_verdict_record` resolves the sha via `git rev-parse "${sha}^{commit}"` before writing, so even a short-sha enqueue records the full 40-character form (same boundary rule as REVIEW-SHA-1).
4. **Tests**: `tests/test_arbiter.sh` section 2b/2c asserts the ff path (#201) and merge path (#202) each file a full-schema green record, a 7-char-sha enqueue records the canonical 40-char sha, and sections 3/4 assert conflict (#203) and integration_red (#204) file NO green record. Suite passes 96/96.
5. **Verification**: `make check` green (21 suites); `make lint` clean (48 shell files: 27 strict, 21 warnings-bar, 0 warnings).
