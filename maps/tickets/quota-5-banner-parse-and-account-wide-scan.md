---
id: QUOTA-5
title: "agy quota probe misses the real two-line banner and scans only the target seat's pane"
type: wayfinder:task
status: backlog
assignee: arch
owns: lib/quota.sh, tests/test_quota.sh
parent: maps/universal-herdr-swarm.md
---

# QUOTA-5 -- make the quota gate see the wall that is actually on screen

## Intended Outcome

`lib/quota.sh gate agy <seat>` reports exhaustion (`ok:<N>s`) when the live agy quota
banner is present, and treats the wall as **account-wide**: a banner in ANY agy seat's
pane defers dispatch to every agy seat.

## Background (receipts, PM audit 2026-10-08)

Three agy seats (looper, agy-docs, reviewer) hit `Individual quota reached` at the
same time; the QUOTA-3 gate and QUOTA-2 supervisor defer never fired.

1. **Parse defect.** The real banner is TWO lines:
   `⚠ Individual quota reached. Please upgrade your subscription to increase your limits.`
   then `Resets in 22m24s.` (`herdr agent read looper-hinchk-stampede --source
   recent-unwrapped --lines 200` shows them at lines 193-194). `quota_probe_kind`
   (`lib/quota.sh:51`) uses a single-line `sed` needing both phrases on one line:
   0 matches on the live pane -> `unknown`. Joining lines with `tr '\n' ' '` first
   yields `22m24s`. `QUOTA_BANNER_REGEX='Individual quota reached.*Resets in'` (line
   121) has the same single-line assumption for `wait-output`.
2. **Fixtures lied.** `tests/test_quota.sh:85-137` use single-line banners (including
   one with "Please upgrade..." joined to "Resets in" on the same line), so the suite is
   green against a banner format that was never real.
3. **Wrong scope.** The wall is per Google account ("Individual"), but the probe reads
   only the dispatch target's own pane. An idle seat with a clean pane returns
   `unknown` -> gate passes -> dispatch walks into a wall that sibling seats already hit.
4. **Prediction caveat (by design, keep).** `unknown` must stay non-blocking: the
   banner appears only after exhaustion, so this ticket makes detection prompt and
   account-wide, not forecasting. It cannot predict the first hit.

## Done-Criteria

1. Probe matches the real two-line banner (capture it verbatim as the test fixture)
   AND the old single-line form; most recent marker still wins.
2. Gate scans every agy seat in `.herdr-swarm/seats.json` (kind agy) and returns the
   longest remaining reset among seats showing a banner; no banner anywhere -> `unknown`.
3. `QUOTA_BANNER_REGEX` / wait-output path handles the split banner.
4. Stale-banner guard: a banner older than its stated reset window must not defer
   forever (state how age is judged; note scrollback has no timestamps).
5. Optional, only if cheap and evidence-backed: a pre-flight "burn" hint (count agy
   dispatches per hour from existing lease/trace data) surfaced as advisory text,
   never a hard block.

## Verification Step

Replay the captured two-line banner against the probe (fails before, passes after);
`make check` green; after promote, one live check with a walled seat.
