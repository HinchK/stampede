# Simple startup and milestone self-improvement

Draft implementation handoff, 2026-11-06. Owning decision: [Agree the migration sequence and build-ready handoff](../../../maps/evolving-harness-swarm/issues/10-design-handoff.md). Source inspection baseline: `5082818`; existing local planning edits are additional context. This document is for human review, not a claim that the behavior is implemented.

## Outcome and boundaries

Connect the existing Stampede foundations into a short coached startup, reliable recovery through Herdr, and optional milestone self-improvement. Preserve the accepted work, authority, recovery, review, and promotion contracts. Reduce repeated questions and duplicated orchestration.

The comparative experiment is bypassed. The proposed team count and shared-worktree change remain on hold; this handoff preserves current topology rather than deciding that question. AGY Flash and ZCode remain the everyday provider preference, with occasional Claude assistance; actual supported routes require readiness verification.

## Approach and reuse

Extend the existing CLI, configuration, brief rendering, project state, and Herdr lifecycle code. A new controller service or separate dashboard would duplicate existing responsibilities and is outside this effort. Removing the existing safety machinery would violate the accepted review/recovery requirements. Reuse is the selected direction.

| Responsibility | Existing foundation | Change needed |
| --- | --- | --- |
| Setup and saved configuration | `lib/setup.py`, `lib/cli/stampede-setup.sh`, `lib/config.sh` | Short coaching phase, saved work brief, self-improvement choice |
| Instructions | `lib/briefs.sh`, `briefs/` | Coaching and improvement instructions; versioned candidate content |
| Startup and recovery | `herdr-loop-swarm.sh`, `lib/providers.sh`, `lib/preflight.sh`, `lib/lifecycle.sh`, `lib/attention.py` | Connect checks, reconciliation, bounded recovery and readiness |
| Reporting | `lib/telemetry.py`, existing worklog/handoff records, `lib/cli/stampede-status.sh` | Attributed four-T summary and failure/collision records |
| Verification and cleanup | `lib/arbiter.sh`, `lib/worktree.sh`, existing review gates | Confirmed-merge closeout, preservation before teardown, resumable receipts |

These are starting points, not a requirement to modify every listed file. Place the smallest necessary change in its existing owner.

## Operator flow

1. **Coach.** Use an available approved provider to clarify the requested outcome, evidence of success, and stopping boundaries. Reuse supplied answers and an existing brief. A returning run asks only what changed. Optional kickoff research remains optional.
2. **Save setup.** Save the agreed short brief with the existing project configuration. Setup and delivery launch remain separate. Changing a brief does not silently change provider choices or permissions.
3. **Launch or recover.** Revalidate access, limits, Git state and actual Herdr sessions. Reattach surviving workers; recover missing startup state within the existing authority. Show a concrete remedy when recovery cannot safely establish readiness.
4. **Deliver.** Use the existing bounded work, review and verification flow. Herdr owns terminal sessions, panes and agent lifecycle; Stampede owns work identity, evidence and limits.
5. **Close a merged milestone.** When self-improvement is enabled, the dedicated agent produces the retrospective and scorecard, accounts for failures/collisions, and coordinates verified worktree cleanup and subsequent bounded improvement work.

Coaching default (accepted by HinchK, 2026-11-06): at most three focused questions, followed by a compact brief. Missing consequential decisions stay explicit; the question limit does not authorize guessing permissions or acceptance criteria. Coaching uses an existing coordinating route, without requiring an additional permanent coaching seat.

## Startup recovery

Use actual native session state and durable project records. Do not infer readiness from an installed binary or a model catalog alone. Reconcile surviving writers before replacement; preserve dirty work and repair history. Repeating an unchanged failing action is not progress. Recovery stays within the accepted run/attempt limits and stops with a useful handoff when those limits or native capabilities prevent continuation.

Never simulate Herdr membership by setting its injected context. Live control and acceptance must occur from an actual managed context. Detachment keeps sessions running and is distinct from stopping work. A restart must not repeat a completed external action or reset permissions, deadlines, explicit stops, or engineering repairs.

## Self-improvement toggle and ownership

Expose one project-level on/off choice through existing setup/configuration. Enabled is the proposed default approved for continuation by HinchK's instruction to proceed. When enabled, exactly one agent is assigned exclusively to self-improvement; it does not take delivery assignments. Trigger its work from recorded events and milestone boundaries rather than spending model turns polling for activity.

The toggle covers this agent and its milestone closeout: retrospective, scorecard, failure/collision accounting and associated-worktree cleanup. Disabled mode schedules none of that feature's work. Ordinary delivery checks and preservation obligations remain in force. Disabling during preservation leaves a truthful checkpoint; it does not permit data loss or mark unfinished cleanup complete.

Apply existing time, permission and improvement allowances. A required closeout that cannot finish before a hard stop remains pending and resumes under valid authority. Completion of a milestone does not grant unlimited improvement time.

## Milestone closeout

Trigger only from evidence that the milestone's code reached `main`. Record milestone identity and included commit references so a restart does not repeat completed closeout actions. The report and preservation receipts must survive deletion of associated worktrees and remain discoverable from normal project status.

| Four T | Accepted measure | Source and missing-data treatment |
| --- | --- | --- |
| Tokens | Usage by agent/model, including self-improvement overhead | Provider/native receipts where attributable; keep input/output/cache categories distinguishable and avoid double counting. Unavailable is unknown. |
| Time | Elapsed milestone time and active human minutes | Recorded milestone events and explicit human-time records. Do not infer human time from agent runtime. |
| Toil | Human interventions, manual recovery steps and repeated work | Linked intervention/recovery/work events; identify estimates or missing records. |
| Trouble | Tool failures, retries and collisions grouped by cause | Preserve distinct attempts and link them to the underlying incident, work and agents. Include ownership, file/Git and session collisions. |

Keep the retrospective short: what wasted effort, what helped, what should change, and where unfinished work was preserved. Record the source and coverage of measurements. Absent instrumentation is not zero trouble or zero human effort. No universal cross-model efficiency claim follows from these figures.

Before worktree removal, establish that its writers stopped. Retain a suitable local branch or create a recovery branch, preserve unmerged commits and snapshot uncommitted/untracked work. Preserve relevant non-Git files separately without committing secrets. Verify every preservation step before removal and record the branch, any separately preserved files, remaining work and next action. Bring the follow-up into the normal checkout without overwriting existing changes. Multiple pending branches are focused sequentially; cleanup does not require simultaneous checkout of every branch. Failed preservation leaves cleanup visibly incomplete.

## Improvement evidence and adoption (accepted by HinchK, 2026-11-06)

Retain the accepted automatic adoption, version history and rollback policy. Replace the bypassed experiment dependency with a small per-candidate gate: before evaluating a candidate, state a measurable four-T improvement target, fixed quality requirements and the affected task family. Compare current/candidate on the motivating problem plus separate relevant regression checks, with independent review and all improvement overhead counted. Repeat the comparison at least twice; two is the initial requirement and the count is tunable when the gate is built. A passing project suite alone does not demonstrate the improvement target.

Only candidates meeting their predeclared target without violating quality or authority boundaries qualify for future work. Inconclusive results retain the current recipe. Keep active workers on their recorded version and retain the previous recipe for rollback. Executable hooks and runtime code use ordinary code checks/review; adoption does not authorize a base merge. This local gate replaces the old numerical experiment gate.

## Small implementation sequence and acceptance

1. **Coached setup and saved brief.** Extend existing setup while preserving configuration and separate launch. Check fresh setup, saved-brief reuse, cancellation and unavailable-provider behavior in the existing setup/config tests.
2. **Recovered startup.** Connect existing readiness and recovery primitives. Check reattachment without duplicate writers, interrupted state, unusable models/catalog failures and an honest stopped/blocked outcome. Preserve existing provider fallback behavior where applicable.
3. **Toggle, exclusive role and milestone closeout.** Verify enabled/disabled behavior, confirmed-merge triggering, repeat/restart handling, attributed four-T records, and inclusion of the improvement agent's own cost.
4. **Safe cleanup and recipe improvement.** Verify preservation of unmerged commits, dirty/untracked work, interrupted cleanup, a dirty normal checkout, candidate isolation, independent evaluation, activation only for future work and rollback.

Use the relevant existing setup/configuration, attention, telemetry, worktree, arbiter and review suites; add focused tests for new behavior. Run `make check` on the actual final candidate. Complete a small visible Herdr walkthrough of setup, useful work, interruption/resume and milestone closeout; include cleanup and a disabled-feature check. Unit tests do not substitute for that native walkthrough.

No mass worktree cleanup, provider spending, merge or deployment is authorized by this document. Implementation preserves existing unrelated edits and validates actual installed native capabilities rather than assuming them.

## Decision traceability

- Startup/work boundaries: [first workload](../../../maps/evolving-harness-swarm/issues/01-workload-and-success.md), [domain contract](../../../maps/evolving-harness-swarm/issues/04-domain-and-loop.md), [operator experience](../../../maps/evolving-harness-swarm/issues/05-runtime-and-experience.md).
- Recovery and authority: [continuity](../../../maps/evolving-harness-swarm/issues/06-continuity-and-integration.md), [resource limits](../../../maps/evolving-harness-swarm/issues/07-replication-and-routing.md), [supervision](../../../maps/evolving-harness-swarm/issues/12-traffic-control-authority.md), [native route limits](../../../maps/evolving-harness-swarm/issues/13-subscription-route-enforcement.md).
- Improvement and closeout: [evolution policy](../../../maps/evolving-harness-swarm/issues/08-harness-evolution.md), amended by [the active handoff decision](../../../maps/evolving-harness-swarm/issues/10-design-handoff.md).

The coaching default and the improvement gate are accepted. The team and shared-worktree change stays deferred (see the map's Not yet specified section); this handoff builds on the current topology. Final handoff acceptance remains pending.
