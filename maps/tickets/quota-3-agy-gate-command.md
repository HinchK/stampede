---
id: QUOTA-3
title: "Point-in-time agy quota gate command (lib/quota.sh gate agy <seat>)"
type: wayfinder:task
status: resolved
assignee: arch-2-hinchk-stampede
owns: lib/quota.sh,tests/test_quota.sh
parent: maps/dispatch-safety-and-review-policy.md
resolution:
  commit: dad86685af5df479509c59eb15bdb3c0a87c3c8e
  reviewed_by: reviewer-hinchk-stampede
  verdict: PASS
  review_file: .herdr-swarm/reviews/QUOTA-3-dad86685af5df479509c59eb15bdb3c0a87c3c8e.md
  integrated_at: dad86685af5df479509c59eb15bdb3c0a87c3c8e
---

# QUOTA-3 -- a scriptable yes/no gate for agy exhaustion

## Intended Outcome

A direct CLI entry point, `bash lib/quota.sh gate agy <seat>`, that returns exit 0 when the seat's account
appears safe to dispatch to and exit 1 when `quota_probe_kind agy <seat>`'s own pane-scan reports exhaustion
(`ok:<N>s`). Point-in-time only -- no blocking, no retry-queue, no new persistent state.

## Background

Chartered via /wayfinder grilling, 2026-10-07, as the shared mechanism for `QUOTA-4` (looper's own brief) and
`pm`'s own standing habit of checking before dispatching to `looper` -- two gaps `QUOTA-2` didn't cover
(it only wired the supervisor's automated reviewer dispatch). `quota_probe_kind agy` already exists in
`lib/quota.sh` (shipped under `QUOTA-1`/`QUOTA-2`) as a sourced shell function; `lib/quota.sh` currently has no
direct CLI dispatch block of its own (confirmed: no `if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]` block at the end
of the file, unlike `lib/headless.sh`/`lib/worktree.sh`) -- only `lib/cli/stampede-quota.sh`'s full
informational table (`stampede quota`) is directly invokable today, and that's the wrong shape for a scriptable
gate (it probes every configured seat kind and prints a table; this needs a single clean exit code for one
specific seat).

## Done-Criteria

1. `lib/quota.sh` gains a CLI dispatch block (same pattern as `lib/headless.sh`) so `bash lib/quota.sh gate agy
   <seat>` works standalone, without requiring the caller to source the file first.
2. `gate agy <seat>` calls `quota_probe_kind agy <seat>` and returns:
   - exit 0 if the probe is `unknown` or `error:*` (no measured signal is not evidence of exhaustion -- never
     fail closed on absence of data here, this is the opposite of a safety check).
   - exit 1 only if the probe matches `ok:[0-9]+s` (a measured, positive exhaustion signal).
3. Prints the raw probe result to stdout either way (so a caller or a human reading output can see *why*,
   not just the exit code).
4. Test coverage in `tests/test_quota.sh` for both exit paths against fixture pane output.
5. `make check` green, 0 shellcheck warnings.

## Verification Step

```bash
bash tests/test_quota.sh
```

## Notes

Deliberately no `--wait`/blocking variant and no persistent retry-queue -- settled in grilling: both consumers
of this (`pm`'s own habit, `looper`'s brief via `QUOTA-4`) already sit inside a human-monitored loop that
naturally retries later; unlike the supervisor (`QUOTA-2`, which runs unattended and needed its own durable
marker), there's nothing here for persistence to protect against.
