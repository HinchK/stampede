---
id: HEADLESS-2
title: "Research: what would a true --headless (no-pane) run mode require?"
type: wayfinder:research
status: backlog
assignee: looper
owns: docs/findings/
parent: maps/universal-herdr-swarm.md
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
