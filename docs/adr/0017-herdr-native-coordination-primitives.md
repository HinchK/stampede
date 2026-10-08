# ADR 0017: Herdr-Native Coordination Primitives — Wait, Explain, Notify

- **Status**: Accepted
- **Date**: 2026-10-07
- **Deciders**: Human driver (charter), arch-1 (author)
- **Epic**: [maps/herdr-native-and-seat-utilization.md](../../maps/herdr-native-and-seat-utilization.md)
- **Tickets**: [HERDR-1](../../maps/tickets/herdr-1-herdr-surface-audit.md), [HERDR-2](../../maps/tickets/herdr-2-wait-output-adoption.md), [HERDR-3](../../maps/tickets/herdr-3-agent-explain-diagnostics.md), [HERDR-4](../../maps/tickets/herdr-4-brief-delivery-modernization.md), [HERDR-5](../../maps/tickets/herdr-5-native-notifications.md)

## Context

The 2026-10-07 session retrospective (`~/Fun/Agathokakological/stampede-notes-10072026.md`,
distilled into `docs/findings/` by HERDR-1) documented three recurring friction classes
where this swarm re-implemented, in shell and in agent habit, coordination primitives
Herdr already ships:

1. **Polling instead of blocking.** Waiting on a specific worker output line
   (`ARCH DONE #…`, quota banners) was done with `herdr agent wait`/`get` timeout-and-
   recheck cycles — dozens per session in the orchestrator's transcript. Herdr's
   `pane wait-output (--match|--regex) [--timeout]` blocks until the pattern appears,
   searches existing output first, and returns the matched line.
2. **Guessing instead of explaining.** Confusing pane state (`focused:true`
   collisions, stale scrollback, `unknown` lifecycle states) was diagnosed by re-reading
   raw pane text. Herdr's `agent explain <target> --verbose` prints the actual
   priority-ordered detection rules and which one fired — ground truth.
3. **Trace-stream-only alerting.** Human-visible incidents (a ~90-minute quota stall)
   surfaced only through the Ops telemetry pane. Herdr's `notification show` delivers a
   native OS notification independently of any pane.

Additionally, `lib/briefs.sh` deliver_brief_nonce still sends `herdr agent prompt`
followed by `sleep 1 && herdr agent send-keys enter`. Herdr 0.9.3's `agent prompt`
"submits text plus encoded Enter and honors the terminal's live bracketed-paste mode"
— the manual keystroke is a legacy double-submission hazard from an older contract.

## Decision

1. **Block, don't poll.** Any code path or standing-brief instruction whose purpose is
   "wait until this pane shows X" uses `herdr pane wait-output` (single-target waits).
   The supervisor's multi-anchor harvest scan (`agent read` + anchored grep across all
   seats each pass) is explicitly **kept** — one read serves several anchor grammars and
   wait-output would serialize it; this is a documented "keep" verdict, not an omission.
2. **Explain, don't guess.** Ambiguous agent state during diagnostics
   (`stampede doctor`, seat-verify failures) calls `herdr agent explain <target>
   --verbose` and shows which detection rule fired, before any re-read heuristic.
3. **Notify, don't hope.** Supervisor human-visible alerts (quota deferral, dead
   letters, `ALERT_BLOCKED`, RED gates) additionally emit `herdr notification show`
   when running inside Herdr; the trace stream remains the durable record.
4. **One submission path.** Brief delivery uses `agent prompt`'s native submission.
   The `sleep 1 && send-keys enter` follow-up is removed only after HERDR-4's live
   probe confirms the installed Herdr's behavior per agent kind (docs say encoded Enter
   is sent; operational folklore says it sometimes is not — the probe settles it, and
   the outcome is recorded as a receipt, not an assumption).
5. **Feature-detect, fail soft.** All adoption goes through capability probes
   (`herdr pane wait-output --help` etc.). On a Herdr without the primitive, the call
   site falls back to today's behavior and logs once — never a hard failure, never a
   synthetic replacement signal.

## Alternatives considered

- **Keep polling everywhere** — rejected: the retrospective shows the cost is real
  (transcript bloat, latency to verdict harvest, human-visible delay on incidents).
- **Socket API event subscriptions** (`herdr api`) instead of CLI waits — deferred:
   promising for the supervisor daemon long-term, but it couples the daemon to
   server-internal schema; CLI primitives with feature detection are the stable surface
   today. Revisit after the audit (HERDR-1) if subscription seams prove load-bearing.
- **Mandate `wait-output` in the supervisor harvest loop** — rejected for the
  multi-anchor scan (see Decision 1); adopted only where the wait is single-target.

## Consequences

- Call sites gain a probe + fallback branch each; the fallback preserves every current
  behavior, so a Herdr version regression degrades to status-quo, not failure.
- Standing briefs (looper, arch) gain herdr-hygiene instructions; like every
  brief-level instruction these are followed-on-best-effort by the agent, which is an
  accepted limit of the brief protocol (same class as QUOTA-4).
- The double-enter removal changes the brief-delivery contract; HERDR-4's probe
  receipt protects against the folklore being version-specific truth.
- Utilization of agy-gh and the opencode arch seats becomes measurable (ROUTE-4
  dashboard), making "right-seat routing" falsifiable rather than vibes.
