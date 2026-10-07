---
id: QUOTA-4
title: "Looper's standing brief checks the agy gate before dispatching to other agy seats"
type: wayfinder:task
status: backlog
assignee: arch
owns: briefs/looper.in.md
parent: maps/dispatch-safety-and-review-policy.md
blocked_by: [QUOTA-3]
---

# QUOTA-4 -- teach looper's brief to check before it dispatches

## Intended Outcome

`briefs/looper.in.md` (the template rendered into `looper`'s standing brief) instructs looper to run `bash
lib/quota.sh gate agy <target-seat>` before dispatching to `reviewer`, `agy-docs`, or `agy-gh` via `herdr agent
prompt` -- and if the gate reports exhaustion (exit 1), to skip the dispatch and report the deferral plainly
rather than attempt it anyway.

## Background

Chartered via /wayfinder grilling, 2026-10-07, alongside `QUOTA-3` (the gate command this depends on). This is
the `looper`-side half of closing the two agy-dispatch gaps `QUOTA-2` left open (it only wired the supervisor's
own automated reviewer dispatch). `pm`'s own equivalent habit (checking before dispatching to `looper` itself)
is not a ticket -- it's adopted directly once `QUOTA-3` lands.

This is a root-anchor-forbidden path (`briefs/`) for `looper` itself to edit -- same reasoning as every other
code/config change this session, routed through `arch`, not self-edited.

## Done-Criteria

1. `briefs/looper.in.md` gains standing instruction: before any `herdr agent prompt` to `reviewer`, `agy-docs`,
   or `agy-gh`, run `bash lib/quota.sh gate agy <that seat's live name>` first.
2. On exit 1 (exhausted): do not send the prompt. Report the deferral (which ticket/seat, that it's deferred)
   plainly, the same way looper already reports other status -- the human-monitored loop (pm re-prompting
   looper, looper reporting back) is the retry mechanism, not anything new built here.
3. On exit 0: dispatch normally, no change in behavior.
4. This does not change looper's dispatch to `arch-1`/`arch-2` (OpenCode, not `agy` -- out of scope, different
   account entirely).

## Verification Step

Human/pm review -- brief text, no test suite applies (same verification class as `BRIEF-1`). Spot-check: does
the brief's wording actually match `QUOTA-3`'s real command syntax and exit-code contract, not a guessed one?

## Notes

This is a behavior change that depends on looper actually following its brief -- same class of reliability
question as every other standing instruction this project gives its agents (e.g. "never use pane run for
cross-pane injection"). It is not independently testable the way `QUOTA-3`'s own exit codes are; that's a
known, accepted limit of brief-level instructions, not a defect in this ticket.
