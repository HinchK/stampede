---
id: EHS
title: "Stampede: an evolving harness swarm for long-horizon engineering"
type: wayfinder:map
status: open
assignee: null
---

# Stampede: an evolving harness swarm for long-horizon engineering

## Destination

Reach a build-ready design for a simpler, provider-independent Stampede rooted in Herdr, with a short prompt-coach startup, recovery from startup failures, and bounded harness self-improvement.

## Notes

- **Scope redirected by HinchK on 2026-11-06:** continue this existing map toward a simple implementation handoff. The comparative experiment is bypassed. Existing decisions remain useful except where this direction changes them; the proposed team and shared-worktree arrangement is on hold pending further direction.
- Intended user: an experienced AI engineer using multiple frontier subscriptions for everyday development and continued learning. Simplicity, continuity, and evidence matter; maximizing active agents or generated code is not an objective.
- **Simplicity reaffirmed on 2026-11-06:** build on [Herdr's native workspace, panes, agent status, and detach/reattach](https://herdr.dev/tui/docs/quick-start/). Add only the work coordination and evidence needed by these decisions; do not build a second terminal manager or a separate benchmark platform.
- **Pilot provider selection, corrected by HinchK on 2026-11-06:** AGY using Flash and ZCode are the everyday routes, with Claude models used occasionally. No Codex panels, including the coordinating/launch panel. This supersedes earlier default-tier suggestions for this pilot; wider provider support remains a product objective. Exact model identifiers and native route readiness must be recorded at launch, not inferred from these product names.
- User direction: custom harnesses, providers working in concert, long-horizon delivery, replication of agent configurations, and an improvement flywheel. [Define the domain contract and smallest useful execution loop](issues/04-domain-and-loop.md) records the settled domain direction for model tiers, research-assisted kickoff, mediation, and optional traffic-control supervision. Example provider-to-role mappings remain research hypotheses.
- The domain-contract decision defines work, harnesses, evidence, handoffs, and separately allowed improvement work. Detailed runtime and authority mechanisms remain downstream decisions. Replication must be distinguished from configuration mutation and from deploying a new runtime version.
- Existing `CONTEXT.md` describes an implementation-oriented Wayfinder map and the current Herdr runtime. This map uses the newly invoked Wayfinder skill's decision-ticket semantics. It does not override the shipped runtime or old map; update the glossary when definitions are actually resolved.
- **Canonical tracker:** local Markdown. This map and `issues/*.md` form one isolated planning epic under `maps/`; decision tickets are intentionally outside `maps/tickets/*.md`, the live implementation intake. No GitHub mirror is created by charting this local map.
- **Wayfinding operations:** frontmatter `id` is identity, `parent` links to this map, `type` is the `wayfinder:*` label, `assignee` is the claim, and `blocked_by` lists local ticket IDs. These local files have no native dependency UI, so the frontmatter relationship is authoritative. The frontier consists of open, unassigned children whose blockers are all resolved; choose the lowest numeric filename first. Claim by setting `assignee: HinchK` and `status: claimed` before work. Resolve by appending a dated resolution under `## Comments`, setting `status: resolved`, and linking one gist here. Do not place answers in the Question section.
- **Session skills:** Wayfinder for map operations; grilling and domain-modeling for human decisions; research for research tickets; prototype for a concrete artifact requiring human reaction. Resolve at most one non-research ticket per session. Human tickets require the human's own answers.
- Research artifacts live in `docs/findings/`; each research ticket records its throwaway `research/<name>` branch and commit. Research facts inform later choices without selecting a provider, budget, or autonomy policy on the user's behalf.
- **Current constraint source:** [Define the first engineering workload and what better means](issues/01-workload-and-success.md) records the settled pilot brief and requirements, which refine the earlier open-constraint framing. The initial pilot is subscription-only; API and local-model support are deferred. [Set replication, routing, resource, and authority limits](issues/07-replication-and-routing.md) records startup opt-in for capacity/quota management and the ongoing backup/alert policy. Harness evolution is scoped by [Define how harness improvements are proposed, evaluated, and adopted](issues/08-harness-evolution.md); runtime changes follow ordinary engineering tasks. Existing protections remain in force while planning.
- Completion requires a traceable, practical design handoff covering the prompt coach, Herdr reuse, startup recovery, self-improvement, existing authority and verification boundaries, and migration sequence. The lightweight evidence rule for adopting improvements remains to be decided; bypassing the comparative experiment does not itself settle that rule. No open decision or unexamined in-scope fog may remain.
- **Milestone closeout, directed by HinchK on 2026-11-06:** the self-improvement feature is toggleable. When enabled, one agent is dedicated exclusively to self-improvement and closes each milestone with code merged to `main` through an efficiency retrospective, failure/collision accounting, associated-worktree cleanup, and the accepted four-T scorecard. Preserve unfinished work on local branches before removing associated worktrees. Details and proposed toggle defaults are recorded in [Agree the migration sequence and build-ready handoff](issues/10-design-handoff.md).
- Reference principles: [OpenAI harness engineering](https://openai.com/index/harness-engineering/) and [Anthropic long-running harnesses](https://www.anthropic.com/research/effective-harnesses-for-long-running-agents). The user-provided Agent-First Engineering PDF is supporting material, not authorization to adopt its automerge or zero-handwritten-code policies.

## Decisions so far

- [Define the first engineering workload and what better means](issues/01-workload-and-success.md): pilot Stampede's guided Herdr setup through a real starter task and stop/resume; prioritize reduced effort, staged run horizons, explicit human boundaries, and per-model token-velocity reporting.
- [Establish supported provider and harness capabilities](issues/02-provider-capabilities.md): bounded interfaces exist, but access, interruption, permissions, and accounting require provider-specific contracts and explicit unknowns.
- [Establish credible methods for evaluating an evolving swarm](issues/03-evaluation-methods.md): separate orchestration, model choice, and adaptation; measure independent outcomes and total effort; current evidence does not establish general swarm superiority.

- [Assess the proposed model and harness routing hypotheses](issues/11-routing-hypotheses.md): documented capabilities support trial candidates; comparative rankings, quota economics, and long-horizon reliability require local evidence.

- [Define the domain contract and smallest useful execution loop](issues/04-domain-and-loop.md): autonomous bounded work with evidence-based completion, contract-lawyer mediation, durable handoffs, and separately allowed improvement work.

- [Choose the runtime boundary and operator experience](issues/05-runtime-and-experience.md): keep setup and launch separate, default to a summary with worker drill-down, and retain existing foundations with Herdr operating sessions and Stampede enforcing the work contract.

- [Define traffic-control supervision and human-proxy authority](issues/12-traffic-control-authority.md): scoped delivery/PR authority with opt-in base merges, work/deadline expiry, lawyer-led contract interpretation, and local versus run-wide pause rules.

- [Establish enforceable isolation for subscription-backed routes](issues/13-subscription-route-enforcement.md): documents native tool-boundary limitations and eligibility checks; the separate-controller recommendation was not adopted, and no route is yet certified.

- [Set replication, routing, resource, and authority limits](issues/07-replication-and-routing.md): use Herdr/provider-native controls, opt-in quota management with backup handoff, preserved repair accounting, and optional scoped secret exposure with managed cycling.

- [Define durable progress, recovery, and integration](issues/06-continuity-and-integration.md): recover within valid authority, integrate at milestone boundaries with offered task-level batching when friction repeats, and preserve pending cycling while holding base merges/final completion.

- [Define how harness improvements are proposed, evaluated, and adopted](issues/08-harness-evolution.md): improve versioned harness recipes, adopt qualifying changes automatically for future work using independent comparisons, and retain scoped rollback; runtime changes use ordinary tasks.

- [Agree the migration sequence and build-ready handoff](issues/10-design-handoff.md): accepted a four-step reuse-first implementation handoff with a three-question coaching default, a per-candidate improvement gate (two repeat comparisons), a toggleable self-improvement agent with milestone closeout, and the current topology as baseline.

## Not yet specified

- The proposed initial team and shared-worktree arrangement, put on hold by HinchK on 2026-11-06. The handoff preserves the current topology; revisit only if HinchK reopens it.

## Out of scope

- [Choose the pilot configurations and freeze the experiment protocol](issues/09-experiment-protocol.md): the comparative experiment and its protocol are bypassed at HinchK's direction.

- A new enforcement controller, permission broker, dedicated controller identity, or added isolation layer; use Herdr and provider-native harness controls per [Set replication, routing, resource, and authority limits](issues/07-replication-and-routing.md).

- Implementing encrypted secret storage or credential-store migration in this pilot. User-maintained files remain the default; an explicit scoped exposure mode with managed cycling is now part of the design. See [Set replication, routing, resource, and authority limits](issues/07-replication-and-routing.md).

- Model-provider API access and local-model support in the initial pilot; HinchK deferred these to a later iteration in [Set replication, routing, resource, and authority limits](issues/07-replication-and-routing.md).

- Implementing or releasing the new runtime, launching project swarms, or executing the comparison experiment in this planning epic.
- Claiming universal swarm superiority, training model weights, or building a commercial multi-user service.
- Changing current promotion permissions, weakening verification, or granting additional spending authority through this map.

- Provider-research and operator-prototype follow-ups, and constraints a pilot might have exposed: both depended on work this map no longer performs. Anything unexpected surfaces during the implementation walkthrough as an ordinary task.
