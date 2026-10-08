---
id: QUOTA-5
title: "agy quota probe misses the real two-line banner and scans only the target seat's pane"
type: wayfinder:task
status: resolved
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

## Resolution (2026-10-08)

Done, all five criteria:

1. **Two-line + legacy match, most recent wins** — the probe joins the pane read
   with `tr '\n' ' '` and matches `Individual quota reached.{0,120}Resets in
   <dur>` (the 120-char bounded gap spans the upgrade sentence of the real form
   and covers the legacy single line); `grep -oE` emits every match in pane
   order, last one wins. Fixtures now carry the real banner verbatim (line 1 +
   `Resets in 22m24s.` on its own line). Replay receipts:
   - BEFORE (pre-change probe on the verbatim fixture): `unknown`
   - AFTER: `ok:1344s` (22m24s), and two-banner scrollback → `ok:600s`.
2. **Account-wide scan** — `quota_gate agy <seat> [target_dir]` probes the named
   seat plus every `kind == "agy"` seat in `<target>/.herdr-swarm/seats.json`
   (default target `$PWD`, so looper's existing call shape is unchanged),
   applies the longest reset, prints a pure `ok:<N>s`/`unknown` stdout line
   (gate callers' `^ok:[0-9]+s$` contract intact) and the walled-seat list on
   stderr. Missing ledger → named-seat-only degrade.
3. **wait-output split banner** — `QUOTA_BANNER_REGEX` is now
   `'Individual quota reached'`: wait-output matches pane *lines*, so the old
   marker+reset spanning regex could never match the two-line form; the marker
   phrase is line 1 of the real banner and the head of the legacy line, and the
   exact reset is measured by the pane-read probe.
4. **Stale-banner guard** — scrollback has no timestamps, so age is judged
   against a first-seen record `<target>/.herdr-swarm/quota-banner-seen.json`
   (`{seat: {seen, reset_s}}`, written by the gate only, atomic tmp+mv). A
   measured banner is trusted while `now <= seen + reset_s + 60s`; past that it
   is dead scrollback text **unless** the measured countdown grew past the
   recorded one + 30s (a new wall instance re-registers — a live wall's
   countdown only decreases). A clean probe clears the seat's record. A frozen
   banner therefore reads stale forever (test proves repeated reads stay
   `unknown`) instead of deferring forever.
5. **Burn hint — deliberately not implemented**: the criterion allowed it only
   if cheap and evidence-backed; telemetry carries no per-dispatch agy events
   (looper prompts don't write traces), so an hourly dispatch count would be
   fabricated data. Recorded here as the reason, not silently dropped.

CLI: `gate <kind> <seat> [target_dir]` (arity 2–3; usage errors still exit 2).
Tests: 15 new assertions in tests/test_quota.sh (verbatim two-line fixture,
recent-wins, account-wide longest + clean-named-seat-deferred, non-agy
exclusion, ledger-less degrade, stale frozen banner twice, new-instance
re-register, record clearing, 3-arg CLI child, non-agy contract unchanged);
HERDR-2 wait argv assertion updated to the new banner regex.

Receipts: `make check` → `All suites green (20)`, `Lint clean`;
tests/test_quota.sh → 72 passed, 0 failed.
