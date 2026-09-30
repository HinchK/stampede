---
id: HEADLESS-2
title: "Research: what would a true --headless (no-pane) run mode require?"
type: wayfinder:research
status: resolved
commit: aad1b88
assignee: looper
owns: docs/findings/
parent: maps/universal-herdr-swarm.md
resolution:
  commit: aad1b88
  findings_file: docs/findings/headless-mode-design.md
github_issue: 75
github_url: "https://github.com/HinchK/stampede/issues/75"
synced_at: "2026-09-30T17:16:14Z"
---

# HEADLESS-2 — headless run mode design research

## Intended Outcome

A design doc (`docs/findings/headless-mode-design.md`) that answers, without implementing anything yet:

1. **Verification mechanism**: today the Suite Gate and `ARCH DONE` harvesting work by the supervisor reading pane
   output via `herdr agent read` / the terminal-anchor regex. If a seat isn't a Herdr pane at all (a pure background
   subprocess), what replaces that? Does it still route through the Herdr daemon, or bypass it (direct subprocess
   management of the vendor CLI)?
2. **Which seats, and triggered how**: this session's working assumption (not yet confirmed with the driver) is an
   *additive* `--headless` mode for unattended dispatch of already-queued tickets — not a wholesale replacement of
   the interactive pane-based system, which stays the default. State this assumption explicitly and flag it as
   unconfirmed.
3. **Brief delivery**: today's nonce file-path protocol assumes a PTY prompt to write into. Does headless dispatch
   still use it, or does a headless seat read its brief file directly on startup?
4. **Blast radius**: what happens to fail-closed guarantees (Suite Gate, partition/lease, human promote gate) in a
   mode with no human watching a pane at all — do any of them implicitly depend on a human being able to *see*
   something going wrong?

## Done-Criteria

1. `docs/findings/headless-mode-design.md` answers all four questions above with citations to the actual current
   code (not speculation).
2. Explicitly recommends a next step (a wayfinder map with real tickets) rather than jumping to implementation —
   this ticket produces a decision the driver can react to, not code.
3. Flags anywhere the destination itself (additive vs. full-replacement, trigger mechanism) needs driver
   confirmation before implementation could safely start.

## Verification Step

Human/pm review of the design doc — no test suite applies to a research ticket.

## Notes

Resolved by research (Skill tool, "research"), not implementation — no code changes, no suite gate. This is
deliberately a stopping point before real implementation tickets get written, since the destination for the bigger
piece of "headless mode" was never actually confirmed with the driver (see `maps/universal-herdr-swarm.md`'s
headless-mode entry and the 2026-09-23 grilling round that didn't reach a shared understanding).

## Resolution

Resolved by research in commit `aad1b88` with the publication of [`docs/findings/headless-mode-design.md`](file:///Users/hinchk/Fun/stampede/docs/findings/headless-mode-design.md):

1. **Verification & Harvesting Mechanism**: Analyzed Herdr daemon vs. direct subprocess management. Demonstrated that Herdr daemon has no pane-less background agent primitive. Recommended direct subprocess management with structured channel/log verification (`loop-bot-herd.sh:734-738`), with refinement turns replacing interactive prompts.
2. **Seat Scoping & Trigger Mechanism**: Established the working assumption of an *additive* batch drain mode (`stampede drain --headless`) rather than a full replacement of the interactive pane system, explicitly flagged as unconfirmed with the driver. Scoped execution seats strictly to workers (`arch-1`, `arch-2`), reviewer (`reviewer`), and supervisor/arbiter daemons, omitting interactive seats (`looper`, `pm`, `docs`, `gh`).
3. **Brief Delivery Protocol**: Demonstrated evolution of Nonce Brief Delivery Protocol ([ADR 0003](file:///Users/hinchk/Fun/stampede/docs/adr/0003-dynamic-seating-and-nonce-brief-delivery.md)) to non-PTY environments via CLI prompt flags (`claude -p`, `opencode run`) or environment variables, preserving <200b pointer efficiency without PTY synchronization hazards.
4. **Blast Radius & Fail-Closed Safety Guarantees**: Audited Suite Gate ([ADR 0001](file:///Users/hinchk/Fun/stampede/docs/adr/0001-fail-closed-profile-and-test-gating.md)), Partition/Lease Gate ([ADR 0012](file:///Users/hinchk/Fun/stampede/docs/adr/0012-task-partitioning-and-disjoint-dispatches.md)), Reviewer Loop (`REV-1`–`REV-5`), and Sovereign Human Promote Gate ([ADR 0009](file:///Users/hinchk/Fun/stampede/docs/adr/0009-arbiter-branch-integration-and-cas-merge.md)), proving all machine gates remain robust without visual monitoring. Identified 3 new headless hazards: runaway re-verdict loops (mitigated by attempt caps), hanging process lease starvation (mitigated by timeouts/eviction), and swallowed alerts (mitigated by dead-letter logging).
5. **No Code / Next Step**: Zero implementation code written; proposed a dedicated Wayfinder Map (`maps/headless-run-mode.md`) for driver architectural alignment and confirmation.
