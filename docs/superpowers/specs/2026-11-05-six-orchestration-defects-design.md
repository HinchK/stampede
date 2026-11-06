# Repair the six orchestration defects

Status: approved by the user on 2026-11-05; implementation authorized.

## Intent and scope

The user requested fixes for the six defects reproduced in the project review
at `fbfbd8e`. Stampede serves one human running several concurrent workers.
Success means that independent review cannot be supplied by the implementer,
verified candidates survive concurrent queue activity, and supported setup and
gate modes reach the integration queue correctly.

This is one bounded repair batch across the existing supervisor, arbiter, role
resolution, and regression suites. Keep Bash 3.2, the existing Python runtime,
current CLI commands, JSON state, and manual human promotion. Provider expansion,
agent topology changes, credential isolation, and performance benchmarking are
outside this repair.

## Approaches

1. **Repair the existing paths in place — recommended, assistant's call.** Reuse
   the review state machine, PID-stamped lock pattern, tree-consistency check,
   and existing role resolver. Add regressions at the actual caller boundaries.
   This addresses all six findings without a data migration or new dependency.
2. **Replace the queue with a transactional database.** This would address
   writer coordination but require a migration and changes to every queue
   consumer. It does not fix the other four mechanisms by itself.
3. **Remove inline gating and require regenerated configuration.** This reduces
   supported paths but breaks existing documented workflows. Preserve these
   workflows and repair their integration instead.

The user approved the in-place approach and the specific choices below.

## 1. Authorize the assigned reviewer

The supervisor currently scans every seat for review anchors and attributes the
sender only after accepting the verdict. Persist the assigned reviewer before
delivering each review request, including quota failover and deferred retries.
Acceptance requires that the sender is that assigned reviewer, differs from the
implementer, and refers to the current pending ticket and canonical commit.
Use the current stored round when validating the assignment. A terminal or
critique state cannot be changed into PASS merely by another output anchor.

Keep `REVIEW VERDICT #<ticket> <sha> PASS|BLOCK` unchanged. Missing assignment in
an older pending record fails closed; redispatch through the normal reviewer
path to establish one. Do not infer permission from whichever seat emitted PASS.
When the configured failover is the implementer, retain the deferred review and
notify the human; retry the primary when its quota clears. Reject unauthorized
anchors without changing the legitimate pending review or consuming its receipt.

Reach: `loop-bot-herd.sh` reviewer dispatch, deferred replay, verdict scanner,
and directive execution; `lib/lifecycle.sh` state transitions and callers;
`tests/test_review_loop.sh` and `tests/test_async_gate.sh` fixtures. Update the
reviewer protocol documentation only where behavior changes.

## 2. Serialize integration queue mutations

Keep the existing drain lock for integration serialization. Introduce one short
queue-writer lock using the existing portable lock pattern; do not hold this
lock while running a project test suite or calling a model.

Every append or replacement of `integration.jsonl` participates: enqueue
deduplication/supersession/append form one transaction; drain status updates and
local/PR promotion bookkeeping use the same writer lock. Use unique temporary
files in the state directory and release the lock after both success and error.
Parsing or write failure preserves the original queue and returns failure.
Keep existing stale-holder recovery and account for Bash 3.2 process identity.

A new enqueue can complete while an integration suite runs. Before advancing
the integration ref and updating the corresponding row, revalidate the selected
queued candidate under the writer lock so supersession cannot be overwritten.
Retain the existing conditional Git ref update and drain ordering.

Reach: all queue writers in `lib/arbiter.sh`, public enqueue/drain/promote entry
points, supervisor enqueue callers, and `tests/test_arbiter.sh`.

## 3. Reject drift during integration tests

Reuse the supervisor's existing definition of a matching candidate: HEAD is the
expected canonical commit, Git inspection succeeds, and tracked/untracked
working files are clean. Move the check into the existing shared shell library
if necessary, preserving its supervisor callers and failure behavior.

Check the arbiter worktree before and after testing the combined candidate.
Drift overrides a successful test exit: leave the integration ref unchanged,
preserve the test log, and record a non-GREEN hand-back that the existing
supervisor can surface to the worker. Use the existing `integration_red` status
with an explicit drift reason to avoid adding a queue state. Do not write an
integrated GREEN receipt for this run. Existing ignored build output remains
outside the Git cleanliness rule, as in the supervisor today.

Reach: `lib/common.sh`, `loop-bot-herd.sh`, `lib/arbiter.sh`, arbiter hand-back
feedback if needed, and arbiter/async gate regressions.

## 4. Preserve the queue's line format

All queue mutations emit compact JSON, exactly one complete object per line.
Existing valid formatted JSON is accepted by the mutation parser and compacted
on the next successful write; malformed input is reported rather than discarded.
Keep ticket IDs and existing row fields intact.

Test the writer with the actual status and attention readers. After an update
to ticket A, queued ticket B must still be counted and integrated A must be
recognized as settled. Include supersession and promotion writes in coverage.

Reach: `lib/arbiter.sh`; `lib/lifecycle.sh` status and `lib/attention.py` readers
as integration-test consumers; arbiter, CLI status, and attention suites.

## 5. Share setup's role interpretation with dispatch

Use the existing `seat_roles` interpretation for both setup and attention,
including descriptive legacy architect roles, standard architect keys, and the
already-supported single renamed architect. Extract that existing logic into a
small shared Python module if required; keep its behavior and public callers.
Preserve user-written descriptive roles, seat names, provider/model pins,
counts, and custom seats. Retain the current isolation and readiness checks.

Verify a shipped-config upgrade through to real attention candidate selection;
testing the rendered text alone is insufficient. Include the existing renamed
architect fixtures and ensure neighboring custom seats stay outside selection.

Reach: `lib/setup.py`, `lib/attention.py`, the shared resolver if extracted,
the Makefile Python compilation list if a module is added, and setup/attention
fixtures and tests.

## 6. Give inline and asynchronous GREEN the same continuation

Extract the existing isolated-seat GREEN continuation from `gate_reap` into one
supervisor helper and call it from both gate implementations after their tree
checks succeed. The review state machine continues to own policy: loop off
enqueues; loop on requests review; the documented docs-only fast path enqueues.
A state-machine error never becomes a direct enqueue. Root-seat behavior and
manual arbiter drain remain unchanged.

Reach: `loop-bot-herd.sh` asynchronous reap and inline harvest paths;
`tests/test_async_gate.sh` and existing review-loop fixtures. Document that
`gate_concurrency = 0` changes execution timing, not review/integration policy.

## Verification and completion

Add failing regressions before changing runtime behavior. Exercise:

- Implementer/other-seat PASS rejection, assigned primary PASS acceptance,
  independent failover acceptance, self-failover deferral, missing assignment,
  stale SHA, duplicate anchors, and BLOCK/re-review round handling.
- Deterministic concurrent enqueue/status replacement, duplicate enqueue,
  supersession, enqueue during a slow drain, and writer error cleanup. Use
  process barriers in test fixtures rather than timing-dependent sleeps.
- Arbiter tests that modify a tracked file, create a visible untracked file,
  move HEAD, and leave the tree unchanged; only the unchanged run advances.
- A queue writer-to-reader round trip with one integrated and one queued row,
  plus preservation of valid legacy formatted records and unknown fields.
- Setup-to-attention selection for shipped, descriptive, and renamed architect
  configurations, with provider/model pins and custom seats retained.
- Both gate modes with review on/off, docs-only fast path, and a repeated
  completion; the same review/queue effects occur exactly once.

Run the affected suites during repair and the complete `make check` gate on the
final tree. Keep all new tests hermetic: scratch Git repositories, stubbed Herdr
and model CLIs, and no live swarm or remote Git changes. Record exactly which
checks ran. Update current user-facing protocol notes when necessary; historical
incident records remain evidence of their original state.

## Builder discretion

The builder chooses helper names, small extraction boundaries, test fixture
placement, and lock cleanup mechanics within these contracts. Keep changes
focused on the six defects; no new dependency or broad framework is needed.
The shared-OS-user security limitation remains an accepted constraint.
