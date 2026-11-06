---
id: EHS-08
title: "Define how harness improvements are proposed, evaluated, and adopted"
type: wayfinder:grilling
status: resolved
assignee: HinchK
parent: maps/evolving-harness-swarm/map.md
blocked_by: [EHS-03, EHS-04, EHS-07]
---

# Define how harness improvements are proposed, evaluated, and adopted

## Question

What may the improvement loop change, and what evidence must a candidate show before it replaces the current configuration?

Choose the initial mutation surface: instructions, context selection, tools, task decomposition, routing, or runtime code. Decide versioning and ancestry, candidate isolation, regression/held-out evaluation, evaluator independence, adoption authority, rollback, and cadence. Address overfitting to recent failures, prompt growth, changes that improve one task family but harm another, and attempts to weaken acceptance checks.

A successful proposal may be to remove a rule or tool. Define how useful lessons are retained without accumulating contradictory instructions.

Account for insights/improvement work at delivery boundaries, as requested in [Define the domain contract and smallest useful execution loop](04-domain-and-loop.md). Its permission and resource envelope must follow [Define traffic-control supervision and human-proxy authority](12-traffic-control-authority.md); a proposed improvement phase cannot silently erase a selected stopping condition. Include directives, hooks, and skills in the candidate-surface discussion, while preserving independent evaluation and the credential boundary.

**Intended Outcome:** A bounded evolution protocol with credible evaluation and rollback.

**Done-Criteria:** Mutable and fixed surfaces, evidence requirements, adoption, rollback, and learning records are explicitly chosen.

**Verification Step:** Trace a real failure through a proposed change, comparison, rejection or adoption, and later regression; keep evaluator changes separately governed.

## Comments

### Harness-evolution decision claimed — 2026-11-06

Claimed for HinchK after the domain/resource decisions and evaluation research resolved. Carry forward separate improvement allowance, milestone-default integration, native Herdr/provider controls, and scoped secret/cycling rules. This is a design conversation, not authorization to mutate harnesses, run paid experiments, or change runtime code.

### Evolution-policy round — awaiting HinchK — 2026-11-06

Three independent choices were submitted. They remain proposals until HinchK answers.

| Decision | Recommendation submitted |
| --- | --- |
| Mutation surface | Improve harness recipes: directives/prompts, context selection, skills, hooks, decomposition guidance, and routing among approved models. Runtime changes are ordinary engineering work through existing review/integration. Neither path silently changes permissions, optional quota settings, or acceptance criteria. |
| Adoption authority | Automatically adopt qualifying versions for future work at the next authorized boundary; active workers retain their recorded version. Keep previous versions for rollback, with evidence and rationale. |
| Evidence | Compare current and candidate on the triggering problem plus separate regression/held-out tasks under independent criteria. Preserve quality and demonstrate measured benefit, counting improvement/evaluation overhead. Inconclusive candidates do not replace current defaults; task-family-specific gains create specialist recipes. |

### Minimal proposed evolution loop

1. Use existing friction/failure/mediation records to identify a specific recurring problem, or propose deleting a redundant directive/tool. Record the hypothesis and expected measurable effect; do not turn every anecdote into another permanent prompt rule.
2. Capture the parent recipe/version, actual provider/model/harness versions, task family, changed files/settings, and fixed evaluation criteria. Use Git versions and existing branches/records; do not build a new registry service or enforcement controller. A candidate may not redefine what counts as success to make its own result pass.
3. Create a candidate copy with a focused change, retaining the current version for matched comparison. Candidate changes do not modify instructions used by active delivery workers or global user/provider configuration. Hooks and skills that execute code still use ordinary relevant checks and review; provider-native controls remain the boundary.
4. Within the separately authorized improvement allowance, compare old/new from equivalent task starting points. Test the motivating failure and held-out/regression behavior, record independent evidence, and include unsuccessful attempts and all evaluation overhead. If the allowance ends, preserve the proposal/results and stop; incomplete evaluation is not promotion evidence.
5. If the agreed adoption criteria are met, record acceptance and activate only for newly admitted work at an authorized boundary. Otherwise reject or retain as an unproven candidate. A candidate that helps one family but regresses others is considered for that family only, not silently made universal. Exact thresholds/repetitions and sampling belong to the experiment-protocol decision.
6. Retain ancestry and the previous working version. On a verified regression, stop assigning new work to the affected recipe and revert the recipe selection; preserve code, receipts, and history. Reverting configuration must not reset engineering repair usage or automatically undo already-integrated project changes. Active work requiring intervention follows the existing mediation/recovery rules.

**Learning record.** Keep the problem, hypothesis, parent/candidate versions, affected task family, evidence, measured benefit/regressions, decision, activation scope, and rollback reason. Consolidate or remove contradictory lessons rather than append an unlimited instruction diary. Raw transcripts and secret values do not belong in recipes, examples, or evaluation artifacts, including when an exposure grant existed for the original work.

**Fixed versus mutable.** The user's goal, selected permissions/stop boundaries, subscription-only pilot scope, startup opt-in capacity/quota choices, exposure recipients/cycling obligation, and independent acceptance rules are not targets for autonomous weakening. The already-approved contract-lawyer may replace a faulty check with an equivalent one, but that correction must be identified and applied comparably; it cannot secretly improve only a candidate's score. Deliberate evaluator/protocol changes require a separate recorded decision and invalidate comparisons made against mismatched criteria.

This is a proposed learning workflow using existing Herdr/harness/Git mechanisms. No mutation, evaluation run, provider use, or adoption has been performed. Source inspection is checking the current recipe/configuration surfaces and whether version pinning is already supported or requires adaptation.

### Evolution policy accepted — 2026-11-06

HinchK selected all three recommendations: **Harnesses first; runtime through ordinary tasks**, **Automatic adoption with version history**, and **Use this evidence standard**.

The improvement loop may propose directives/prompts, context-selection, skills/hooks, decomposition guidance, and approved-model routing changes. Runtime changes use ordinary engineering tasks and existing review/integration. Neither path widens permissions, enables optional quota controls without startup choice, or weakens agreed completion criteria.

Qualifying recipe versions may be adopted automatically for future work at the next authorized work boundary, with rationale/evidence and rollback history. Active workers remain on their recorded version. Compare against the current version on the triggering problem and separate regression/held-out tasks using independent criteria, preserve quality, and establish measured benefit including improvement/evaluation overhead. Inconclusive candidates leave the current version in place; task-family-specific gains produce specialist recipes rather than universal replacement.

The source check and failure-to-adoption walkthrough will complete the resolution. No actual candidate evaluation or adoption has occurred.

### Source grounding — 2026-11-06

Read-only inspection found reusable [role-brief rendering](../../../lib/briefs.sh#L58), [launch-time brief delivery](../../../lib/briefs.sh#L168), and [provider/model/role configuration](../../../lib/config.sh#L216). Rendered briefs currently use fixed filenames; re-rendering can change a shared file without demonstrating which content an already-running agent adopted. [Existing-agent handling](../../../herdr-loop-swarm.sh#L518) bypasses fresh delivery, while [provider fallback](../../../herdr-loop-swarm.sh#L558) can change the actual provider/model from the configured primary. Record actual delivered content and effective route, not just a template filename or configured alias.

[Native model configuration](../../../lib/providers.sh#L161) is distinct from brief content; changing an instruction does not establish a tool-permission change. [Combined-tree gates](../../../lib/arbiter.sh#L385) validate resulting code/configuration changes but do not establish comparative harness improvement. Immutable candidate provenance, held-out evaluation, adoption, and rollback remain new design work. No live reload, model behavior, or improvement was tested.

### Resolution — 2026-11-06

HinchK accepted the harness-first surface, automatic qualified adoption with version history, and the independent comparison standard. The proposed evolution loop above is adopted with the following concrete interpretation and limits.

**Mutable surface and authority.** Directives/prompts, context selection, skills/hooks, decomposition guidance, and routing among approved eligible models may be improvement candidates. Runtime changes become ordinary engineering tasks through existing review and milestone-default integration. A skill/hook that changes executable behavior still receives relevant code review/checks; calling it a recipe does not exempt it. Goals, permissions, stopping conditions, optional capacity/quota choices, secret recipients/cycling obligations, and acceptance requirements cannot be weakened by improvement work. Use Herdr and provider-native harnesses; no new registry service, enforcement controller, broker, or isolation layer.

**Candidate lineage and delivery.** Use Git to retain the parent recipe, candidate changes, and rollback version. Record the rendered instructions/context selection, effective provider/model/harness versions, relevant native settings, task-family scope, and actual worker/session/attempt identity for each trial. Template paths or rolling model aliases alone are insufficient provenance. Render candidate material into version-specific work/attempt files rather than overwrite instructions active workers may reread. Apply native configuration changes only where the provider supports an independent candidate/session configuration. If a setting is shared or live-reloaded, defer changing it until the affected workers are finished; do not claim active-version pinning from launch-time delivery alone. This is a required adaptation of the existing rendering/configuration flow, not a separate product subsystem.

**Evaluation and adoption.** Identify a specific failure/friction pattern or simplification opportunity, state a hypothesis, and compare candidate/current from equivalent task starting points. Include the motivating problem and separate regression/held-out tasks. Fix independent criteria before observing candidate results; neither the candidate nor its author may rewrite them to pass. Keep outcome evidence independent of self-report, with review separate from generation. A contract-lawyer correction to a genuinely faulty check must be equivalent, recorded, and applied consistently; changed/mismatched grading invalidates the comparison and requires reevaluation. Repeated exposure of evaluation cases must be tracked to avoid calling tuned-on cases held out.

Preserve the agreed quality floor and demonstrate a measured benefit such as reduced human effort, fewer repeated failures, or lower consumption, counting rejected candidates, experimentation, review, and all improvement overhead. Preserve the primary effort-reduction objective; exact thresholds, repetitions, and allowed tradeoffs are frozen in the next protocol decision. Token velocity is diagnostic, not proof of improvement. A green project suite alone is insufficient. Inconclusive evidence leaves the current recipe in use; a gain limited to a task family produces a scoped specialist rather than a global default.

Qualified candidates may become the selected recipe automatically at the next authorized work boundary, with a recorded version, evidence, rationale, and scope. New work uses the adopted version; active work retains its recorded version. Adoption does not start unauthorized work, bypass the separate improvement allowance, auto-merge runtime/base changes, or continue after a stop. If the allowance ends before evaluation finishes, retain the candidate and partial evidence without adoption. The experiment protocol's numeric rules must exist before automatic qualifying decisions can operate.

**Rollback and learning.** Keep the previous accepted recipe readily selectable. When evidence establishes a regression, stop assigning affected new work to that recipe and revert selection to the last suitable version within the existing authority. Preserve worker/code state, repair usage, receipts, and history; recipe rollback is not automatic reversal of integrated project changes or external effects. Record the regression and mediate affected active work using the continuity contract. Consolidate/remove contradictory or obsolete directives instead of accumulating every lesson. Deleting a rule or tool can be the winning candidate. No raw secrets or secret-bearing transcripts enter recipes, examples, or evaluation artifacts.

**Failure-to-learning walkthrough (hypothetical, no measured result).** Repeated handoffs omit verification evidence. Record that pattern and propose a smaller handoff directive requiring evidence references and a next action. Compare against the current directive on the triggering case and separate handoff/regression tasks. If quality is preserved and the agreed metrics improve after accounting for overhead, adopt for future eligible work at the next boundary. If it merely passes the motivating case, costs more human work, weakens checks, or produces inconclusive evidence, retain the current version. If later tasks expose a regression, revert the recipe selection, preserve the failure record, and consider narrower task-family scope. Neither the motivating failure nor a later regression authorizes changing the evaluator to rescue the candidate's score.

**Evidence and next step.** The user explicitly accepted all three policy choices; repository inspection identified existing mechanisms and their gaps. No candidate has been run, measured, adopted, or rolled back in the runtime. [Choose the pilot configurations and freeze the experiment protocol](09-experiment-protocol.md) is now unblocked and must set workloads, trial design, quality/benefit thresholds, accounting, and held-out treatment before implementation can claim an effective improvement loop.
