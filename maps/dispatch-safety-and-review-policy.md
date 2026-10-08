# Wayfinder Map: Dispatch Safety & Review Policy

**Charted:** 2026-10-07 (pm, via /wayfinder grilling with the driver) · **Supersedes the relevant fog in**
`maps/public-multi-provider.md` ("Auto-throttling / rerouting on quota exhaustion") and
`maps/autonomous-reviewer-loop.md` (all three of its prior "Not yet specified" entries, one of which stays fog
here too).

## Destination

Two tracks, chartered together because both surfaced from this session's real incidents and both got settled
tight enough in grilling to ticket now:

1. **Close the agy-dispatch quota loop one level up.** `QUOTA-2` solved it for the supervisor's automated
   reviewer dispatch; this closes it for the two remaining dispatch paths that actually touched the real
   incident — `pm`'s own dispatch to `looper`, and `looper`'s own dispatch to `reviewer`/`agy-docs`/`agy-gh` —
   via one shared, testable gate command rather than brief text alone.
2. **Resolve the reviewer loop's open policy questions.** Docs/maps-only commits get a decided fast-path
   (built this epic); multi-reviewer quorum gets a real decision (built or explicitly deferred, not left as a
   bare fog note); inline TUI diff inspection stays fog — it needs its own research pass before it's even
   decidable, let alone buildable.

## Notes

- Domain: `lib/quota.sh` (gate command), `briefs/looper.in.md` (standing brief), `lib/lifecycle.sh`/
  `loop-bot-herd.sh` (review-loop dispatch), `docs/adr/` (quorum decision, if one lands).
- Core Invariant, unchanged: promote/push stay human-only; no cross-pane injection; never trust a
  self-reported "done" without independent verification.
- `pm`'s own adoption of the gate command (checking before dispatching to `looper`) is not a ticket — it's a
  habit `pm` adopts directly once `QUOTA-3` lands, same as any other standing-practice change.

## Decisions so far

- 2026-10-07 (charting): both agy-dispatch gaps (pm→looper, looper→target) addressed together, one shared
  gate command — cheaper than two mechanisms for the same underlying signal.
- 2026-10-07 (charting): the gate is a testable shell command (`QUOTA-3`), not brief text alone — same lesson
  `GATE-1` already taught this project about promote-gate enforcement.
- 2026-10-07 (charting): simple point-in-time gate, no new retry-queue — unlike the supervisor (`QUOTA-2`,
  which runs unattended), both `pm` and `looper` already sit inside a human-monitored loop that naturally
  retries; building persistence here would duplicate that for no benefit.
- 2026-10-07 (charting): auto-approve scope is docs/maps paths only (`REV-06`) — test-file-only changes stay
  reviewed, since weakening a test is a real way to hide a defect under cover of "just tests."
- 2026-10-07 (charting): multi-reviewer quorum (`REV-07`) is policy-design-only for this epic — only one
  reviewer kind/seat exists today (`default_kind = "agy"`), so building actual quorum infrastructure is a
  separably-sized future ticket once the policy itself is decided.
- 2026-10-07 (execution): QUOTA-3 resolved (dad8668) — point-in-time gate command `lib/quota.sh gate agy <seat>` passed review and integrated.
- 2026-10-07 (execution): REV-06 resolved (823365f) — docs/maps fast-path passed review and merged into integration at bf84323.
- 2026-10-07 (execution): QUOTA-4 resolved (35a6e49) — looper standing brief gates AGY dispatches, passed review and merged into integration at 2ee247e.
- 2026-10-08 (execution): FALLBACK-1 resolved (b054afc) — standby orchestrator seat with takeover and stand-down implemented in lib/standby.sh, briefs/looper-standby.in.md, tests/test_standby.sh, and swarm.config.toml.
- 2026-10-08 (execution): CI-FIX-3 resolved (564bde7) — test_standby sed replacement made portable across BSD/macOS and GNU/Linux.

## Tickets

| Ticket | Seat | Status | Blocked by | Synopsis |
|---|---|---|---|---|
| **QUOTA-3** | arch-2-hinchk-stampede | **resolved** (dad8668) | — | Build `lib/quota.sh gate agy <seat>` — point-in-time exit-code check, tested |
| **QUOTA-4** | arch-2-hinchk-stampede | **resolved** (35a6e49) | QUOTA-3 | Wire the gate into `looper`'s standing brief before it dispatches to `reviewer`/`agy-docs`/`agy-gh` |
| **REV-06** | arch-1-hinchk-stampede | **resolved** (823365f) | — | Docs/maps-only commits fast-path past the reviewer dispatch, straight to enqueue |
| **FALLBACK-1** | arch-1-hinchk-stampede | **resolved** (b054afc) | — | Standby orchestrator seat: quota-triggered, single-command takeover and stand-down |
| **CI-FIX-3** | arch-1-hinchk-stampede | **resolved** (564bde7) | — | test_standby uses BSD 'sed -i ""' — fails on ubuntu CI, main red again after FALLBACK-1 |
| **REV-07** | — (decision, unclaimed) | backlog | — | Decide multi-reviewer quorum policy — build, or accepted-limit ADR; needs its own grilling session |

All five implementation tickets (`QUOTA-3`, `QUOTA-4`, `REV-06`, `FALLBACK-1`, `CI-FIX-3`) are resolved. `REV-07` (quorum decision) remains on backlog.

## Not yet specified

- Inline TUI review-diff inspection (visualizing reviewer critique comments directly within an Ops or Herdr
  terminal view) — needs a research pass on what Herdr's pane model can actually render before it's
  specifiable as a ticket.

## Out of scope

- Extending quota probing beyond `agy` to `opencode`/`claude` kinds — no known parseable signal for either yet;
  would need its own research ticket before anything here could depend on it.
